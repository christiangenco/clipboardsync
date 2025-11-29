#!/usr/bin/env ruby
require 'open3'
require 'shellwords'
require 'uri'

class LinuxClipboardMonitor
  REMOTE_HOST = "Max.local"
  REMOTE_USER = "cgenco"
  TEMP_IMAGE_PATH = "/tmp/linux_clipboard_sync_image.png"

  def initialize
    @previous_content = nil
    @previous_type = nil
    puts "⚡️ Linux -> MacOS Clipboard Sync started..."
    puts "   (Target: #{REMOTE_HOST})"
    puts "   (Polling `wl-paste` every 1 second)"
  end

  def start
    loop do
      check_clipboard
      sleep 1
    end
  rescue Interrupt
    puts "\n👋 Stopped."
  end

  private

  def check_clipboard
    # 1. Check available MIME types
    # wl-paste --list-types returns a list of available mime types
    mime_output, status = Open3.capture2('wl-paste --list-types')
    
    # If failed or empty, skip
    return unless status.success? && !mime_output.empty?

    mime_types = mime_output.split("\n").map(&:strip)
    current_type = determine_type(mime_types)
    
    # 2. Retrieve content based on type for change detection
    current_content = nil
    case current_type
    when :files
      current_content, _ = Open3.capture2('wl-paste --type text/uri-list --no-newline')
    when :image
      # Get binary image data
      current_content, _ = Open3.capture2('wl-paste --type image/png')
    when :text
      # We use --no-newline to get raw content, but we'll also strip trailing whitespace
      # to avoid infinite loops with the MacOS monitor which usually adds a newline via `echo`.
      raw_content, _ = Open3.capture2('wl-paste --no-newline')
      current_content = raw_content&.strip
    end

    # 3. Compare with previous state
    # Only sync if content exists and has changed
    if current_content && !current_content.empty? && current_content != @previous_content
      puts "\n" + "-" * 40
      # Debug: show exact content to help diagnose loops
      # puts "DEBUG: Content mismatch! Old: #{@previous_content.inspect} New: #{current_content.inspect}"
      
      handle_change(current_type, current_content)
      
      @previous_content = current_content
      @previous_type = current_type
    end
  end

  def determine_type(mime_list)
    return :files if mime_list.include?('text/uri-list')
    return :image if mime_list.any? { |m| m.start_with?('image/') }
    
    # Default to text
    :text
  end

  def handle_change(type, content)
    case type
    when :files
      handle_file_sync(content)
    when :image
      handle_image_sync(content)
    when :text
      handle_text_sync(content)
    end
  end

  def handle_text_sync(content)
    preview = content.length > 60 ? content[0..60].gsub(/\n/, ' ') + "..." : content.gsub(/\n/, ' ')
    puts "📝 TEXT: \"#{preview}\""
    
    # Escape for shell safely
    # Use printf instead of echo to avoid adding extra newlines
    cmd = "printf %s #{content.shellescape} | ssh #{REMOTE_HOST} pbcopy"
    puts "   [Syncing] -> #{REMOTE_HOST}..."
    
    Thread.new { system(cmd) }
  end

  def handle_image_sync(content)
    timestamp = Time.now.strftime("%Y-%m-%d_%H-%M-%S")
    filename = "clipboard_#{timestamp}.png"
    puts "🖼️  IMAGE: #{content.bytesize} bytes"
    
    # Save locally to temp file
    File.binwrite(TEMP_IMAGE_PATH, content)
    
    remote_dir = "Downloads/"
    remote_full_path = "/Users/#{REMOTE_USER}/#{remote_dir}#{filename}"
    
    # AppleScript to set clipboard to the FILE object (Finder style copy)
    # This allows pasting into Finder (as a file) and usually works for apps too (as an upload)
    applescript = <<~SCRIPT
      set the clipboard to (POSIX file "#{remote_full_path}")
    SCRIPT

    # 1. SCP image to remote Downloads with timestamp
    scp_cmd = "scp #{TEMP_IMAGE_PATH} #{REMOTE_HOST}:#{remote_dir}#{filename}"
    
    # 2. Run AppleScript
    ssh_cmd = "ssh #{REMOTE_HOST} 'osascript -' <<'EOF'
#{applescript}
EOF"
    
    puts "   [Syncing] -> #{REMOTE_HOST}:~/Downloads/#{filename}..."
    Thread.new do
      if system(scp_cmd)
        system(ssh_cmd)
      end
    end
  end

  def handle_file_sync(uri_list)
    # uri_list contains lines like file:///home/cgenco/file.txt
    
    # Parse and validate local paths
    paths = uri_list.lines.map(&:strip).map do |uri|
      begin
        path = URI.parse(uri).path
        path = URI.decode_www_form_component(path) if path
        path
      rescue URI::InvalidURIError
        nil
      end
    end.compact.select { |p| File.exist?(p) }

    if paths.empty?
      puts "⚠️  File format detected but no valid local files found."
      return
    end

    # We'll sync the first file found
    path = paths.first
    filename = File.basename(path)
    
    # Target: ~/Downloads/ on macOS
    remote_dir = "Downloads/" 
    remote_full_path = "/Users/#{REMOTE_USER}/#{remote_dir}#{filename}"
    
    puts "📁 FILE: #{filename}"
    puts "   (Syncing to #{REMOTE_HOST}:~/Downloads/)"
    
    # AppleScript to set clipboard to a FILE OBJECT (Finder style copy)
    # This allows you to paste the file itself, not just the path text
    applescript = <<~SCRIPT
      set the clipboard to (POSIX file "#{remote_full_path}")
    SCRIPT
    
    # 1. SCP file to Downloads
    scp_cmd = "scp #{path.shellescape} #{REMOTE_HOST}:#{remote_dir}"
    # 2. Run AppleScript to set clipboard
    # USE HEREDOC FOR SAFETY like we did for images
    ssh_cmd = "ssh #{REMOTE_HOST} 'osascript -' <<'EOF'
#{applescript}
EOF"

    puts "   [Syncing] -> SCP & Clipboard Set..."
    Thread.new do
      if system(scp_cmd)
        system(ssh_cmd)
      end
    end
  end
end

LinuxClipboardMonitor.new.start
