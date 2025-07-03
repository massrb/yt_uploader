require "bundler/setup"
require "mp3info"
require 'yaml'
require 'optparse'
require_relative 'video_uploader'

# upload with google cloud

options = {}

OptionParser.new do |opts|
  opts.banner = "Usage: script.rb [options]"

  opts.on("-f FILENAME", "--file FILENAME", "Specify source mp4 filename") do |f|
    options[:filename] = f
  end

  opts.on("-p PREFIX", "--prefix PREFIX", "Specify a prefix string for derrived segments") do |p|
    options[:prefix] = p
  end

  opts.on("-b SEGMENT", "--begin SEGMENT", "Begin at segment number SEGMENT") do |p|
    options[:start_seg] = p
  end

  opts.on("-s", "--show", "Just show, don't actually run") do
    options[:show_only] = true
  end

  opts.on("-c", "--continuous", "convert segments continuoulsy") do
    options[:continuous] = true
  end

  opts.on("-v", "--video", "Convert the next available segment file(s) to video") do
    options[:to_video] = true
  end

end.parse!

# Use the parsed option
if options[:filename]
  puts "Filename provided: #{options[:filename]}"
else
  puts "No filename given. Use -f to specify one."
end

class Mp3Processor

  def initialize(options)
    @config = YAML.safe_load(File.read('config.yml'), aliases: true)
    @working_dir = @config['working_dir']
    @fpath = "#{@working_dir}/#{options[:filename]}"
    @prefix = options[:prefix] || 'segment'
    @show_only = options[:show_only]
    @to_video = options[:to_video]

    # process one video at a time and exit if false
    @continuous = options[:continuous]
    @start_seg = options[:start_seg]
  end

  def format_duration(seconds)
    Time.at(seconds).utc.strftime("%H:%M:%S")
  end

  def to_mp3(attr)
    cmd = %Q(ffmpeg -y -i "#{@fpath}" -ss #{attr[:start_time].round(2)} ) +
                %Q(-t #{attr[:duration].round(2)} -acodec copy "#{attr[:filename]}.mp3")
    puts cmd
    system(cmd) unless @show_only
  end

  def create_video(fpath)
    image_path = "#{@working_dir}/image.jpeg"
    if File.exist?(image_path)
      cmd = %Q(ffmpeg -loop 1 -i "#{image_path}" -i "#{fpath}.mp3" ) +
            %Q(-c:v libx264 -c:a aac -b:a 192k -shortest ) +
            %Q(-movflags +faststart "#{fpath}.mp4")
    else
      cmd = %Q(ffmpeg -f lavfi -i color=c=black:s=1280x720:d=0.1 -i "#{fpath}.mp3" ) + 
            %Q(-c:v libx264 -c:a aac -shortest -pix_fmt yuv420p "#{fpath}.mp4")
    end
    puts "Create video from mp3 .."
    puts cmd
    system(cmd)
  end

  def to_video(fpath, segment)
    video_path = "#{fpath}.mp4"
    if !File.exist?(video_path)
      create_video(fpath)
    end
    puts 'Upload Video ..'
    VideoUploader.new(video_path, segment).upload_video
    if @continuous
      File.delete(video_path)
    end
  end

  def process
    Mp3Info.open(@fpath) do |mp3|
      overlap = 30
      total_duration = mp3.length
      puts "Length: #{total_duration.round(2)} seconds"
      puts "#{format_duration(total_duration)}"
      raise "file is not big enough to split up" if total_duration < 4000
      num_hours = total_duration / 3600
      segment_length = (total_duration + (num_hours - 1) * overlap).to_f / num_hours
      puts "How many hours: #{num_hours.round(2)} seconds"
      puts "segment length:#{segment_length.round(2)}\n\n"
      count = 0
      seg = @start_seg&.to_i || 1

      while seg <= num_hours.ceil
        start_time = (seg - 1) * (segment_length - overlap)
        end_time = start_time + segment_length

        # Ensure we don't exceed the total duration on the last segment
        end_time = [end_time, total_duration].min
        duration = [segment_length, total_duration - start_time].min

        puts "Segment #{seg}:"
        puts "  Start: #{start_time.round(2)}s"
        puts "  End:   #{end_time.round(2)}s"
        puts "  Duration: #{duration.round(2)}s"
        filename = "#{@working_dir}/#{@prefix}_#{seg}"
        if @to_video
          if File.exist?("#{filename}.mp3")
            count += 1
            to_video(filename, seg)
            puts 'Video done ..'
            break if !@continuous || count >= 3
          else
            puts "\nNo video file !"
            break
          end
        else
          to_mp3(filename: filename, duration: duration, start_time: start_time)
          break if !@continuous || count >= 3
        end
        seg += 1
        puts
      end
    end
  end
end

processor = Mp3Processor.new(options).process





