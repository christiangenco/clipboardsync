#!/usr/bin/env ruby
require 'shellwords'
require 'uri'

class ClipboardSync
  REMOTE_HOST = "archy.local"
  TEMP_IMAGE_PATH = "/tmp/clipboard_sync_image.png"
  # dynamic wayland display detection
  WAYLAND_ENV_SETUP = "export XDG_RUNTIME_DIR=/run/user/$(id -u); export WAYLAND_DISPLAY=$(cd $XDG_RUNTIME_DIR && ls wayland-[0-9]* 2>/dev/null | head -n 1);"
  
  def initialize
    @last_hash = nil
    puts "⚡️ Clipboard Sync Monitor started..."
    puts "   (Prioritizing: Files > Images > Text)"
  end

  def start
    loop do
      check_clipboard
      sleep 0.5
    end
  rescue Interrupt
    puts "\n👋 Stopped."
  end

  private

  def check_clipboard
    # Get raw clipboard info string for change detection
    # format is roughly: "«class furl», 123, «class utf8», 456..."
    info_str = `osascript -e 'try' -e 'return (clipboard info) as string' -e 'end try' 2>/dev/null`.force_encoding('UTF-8').strip
    
    current_hash = info_str.hash

    if @last_hash && current_hash != @last_hash
      # Clipboard changed!
      determine_and_sync(info_str)
    end
    @last_hash = current_hash
  end

  def determine_and_sync(info_str)
    puts "-" * 40
    # Debug: Print detected types for troubleshooting
    puts "🔍 Raw Info: #{info_str[0..100]}..." 

    # 1. Check for Files
    # Look for 'furl' (File URL) or 'alis' (Alias)
    if info_str.match?(/class furl|class alis|file url/i)
      if handle_file_sync
        return
      end
      puts "⚠️  File detection failed, falling back to content check..."
    end

    # 2. Check for Images
    if info_str.match?(/PNGf|JPEG|TIFF|8bps/i)
      handle_image_sync
      return
    end

    # 3. Fallback to Plain Text (includes any rich text)
    handle_text_sync
  end

  def handle_file_sync
    path = ""
    
    # Method 1: pbpaste
    # Note: MacOS often returns a file reference URL (file:///.file/id=...) 
    # which is useless for us. We must check for that.
    begin
      url = `pbpaste -Prefer public.file-url`.strip
      unless url.empty? || url.include?("/.file/id=")
        parsed_path = URI.parse(url).path
        parsed_path = URI.decode_www_form_component(parsed_path) if parsed_path
        if parsed_path && File.exist?(parsed_path)
          path = parsed_path
        end
      end
    rescue => e
      puts "   (URI Parse Error: #{e.message})"
    end

    # Method 2: AppleScript (Robust 'furl' to POSIX conversion)
    if path.empty?
      script = <<~APPLESCRIPT
        try
          set clipboardData to (the clipboard as «class furl»)
          return POSIX path of clipboardData
        on error
          return ""
        end try
      APPLESCRIPT
      
      path = `osascript -e '#{script}'`.strip
    end
    
    if !path.empty? && File.exist?(path)
      filename = File.basename(path)
      remote_dir = "~/Downloads/"
      
      puts "📁 FILE DETECTED: #{path}"
      puts "   (Syncing file content + registering path on Linux clipboard)"
      
      # 1. scp the file
      scp_cmd = "scp #{path.shellescape} #{REMOTE_HOST}:#{remote_dir}"
      
      # 2. ssh to register it with wl-copy
      # We use readlink -f to ensure absolute path, required for file:// URIs
      remote_file_ref = "#{remote_dir}#{filename.shellescape}"
      register_cmd = "ssh #{REMOTE_HOST} '#{WAYLAND_ENV_SETUP} echo file://$(readlink -f #{remote_file_ref}) | wl-copy -t text/uri-list'"
      
      puts "   [Syncing]: #{scp_cmd} && #{register_cmd}"
      Thread.new do
        system(scp_cmd)
        system(register_cmd)
      end
      return true
    else
      return false
    end
  end

  def handle_image_sync
    # Save clipboard content to a temp PNG file
    script = <<~APPLESCRIPT
      try
        set theFile to (POSIX file "#{TEMP_IMAGE_PATH}")
        set theOpenedFile to open for access theFile with write permission
        set eof of theOpenedFile to 0
        --- Prefer PNG, fallback to TIFF
        try
          write (the clipboard as «class PNGf») to theOpenedFile
        on error
          write (the clipboard as TIFF) to theOpenedFile
        end try
        close access theOpenedFile
        return "OK"
      on error
        try
          close access (POSIX file "#{TEMP_IMAGE_PATH}")
        end try
        return "ERROR"
      end try
    APPLESCRIPT

    result = `osascript -e '#{script}'`.strip
    
    if result == "OK" && File.exist?(TEMP_IMAGE_PATH)
      size = File.size(TEMP_IMAGE_PATH)
      puts "🖼️  IMAGE DETECTED: #{size} bytes"
      puts "   [Local Cache]: #{TEMP_IMAGE_PATH}"
      cmd = "scp #{TEMP_IMAGE_PATH} #{REMOTE_HOST}:/tmp/clip.png && ssh #{REMOTE_HOST} '#{WAYLAND_ENV_SETUP} wl-copy --type image/png < /tmp/clip.png'"
      puts "   [Syncing]: #{cmd}"
      Thread.new { system(cmd) }
    else
      puts "❌ Image detected but failed to save."
    end
  end

  def handle_text_sync
    content = `pbpaste`.force_encoding('UTF-8')
    if content.strip.empty?
      puts "∅ Empty clipboard or unknown format."
      return
    end
    
    preview = content.length > 60 ? content[0..60].gsub(/\n/, ' ') + "..." : content.gsub(/\n/, ' ')
    puts "📝 TEXT DETECTED: \"#{preview}\""
    # For syncing text, we might pipe it over ssh
    cmd = "echo #{content.shellescape} | ssh #{REMOTE_HOST} '#{WAYLAND_ENV_SETUP} wl-copy'"
    puts "   [Syncing]: #{cmd}"
    Thread.new { system(cmd) }
  end
end

ClipboardSync.new.start
