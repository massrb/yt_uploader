
# Example:
# 
# ruby prep_video.rb -f 'Meditation Audiobook [G7iFNvRUxVU].mp3' -p 'how-to-meditate' -v
# 

require 'google/apis/youtube_v3'
require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'fileutils'

OOB_URI = 'urn:ietf:wg:oauth:2.0:oob'.freeze
APPLICATION_NAME = 'YouTube API Ruby Upload'
CREDENTIALS_PATH = 'credentials.json'
TOKEN_PATH = 'token.yaml'
SCOPE = Google::Apis::YoutubeV3::AUTH_YOUTUBE_UPLOAD

class VideoUploader

  def initialize(video_path, segment)
    @video_path = video_path
    # Main
    @youtube = Google::Apis::YoutubeV3::YouTubeService.new
    @youtube.client_options.application_name = APPLICATION_NAME
    @youtube.authorization = authorize

    @video_path = video_path
    @config = YAML.safe_load(File.read('config.yml'), aliases: true)
    @title = "#{@config['title']} - Part #{segment}"
    @description = @config['description']
    @tags = @config['tags']
  end

  def authorize
    client_id = Google::Auth::ClientId.from_file(CREDENTIALS_PATH)
    token_store = Google::Auth::Stores::FileTokenStore.new(file: TOKEN_PATH)
    authorizer = Google::Auth::UserAuthorizer.new(client_id, SCOPE, token_store)
    user_id = 'default'
    credentials = authorizer.get_credentials(user_id)
    if credentials.nil?
      url = authorizer.get_authorization_url(base_url: OOB_URI)
      puts "Open the following URL in your browser and authorize the application:"
      puts url
      print 'Enter the authorization code: '
      code = gets
      credentials = authorizer.get_and_store_credentials_from_code(
        user_id: user_id, code: code, base_url: OOB_URI
      )
    end
    credentials
  end

  def upload_video
    video = Google::Apis::YoutubeV3::Video.new(
      snippet: Google::Apis::YoutubeV3::VideoSnippet.new(
        title: @title,
        description: @description,
        tags: @tags,
        category_id: '22' # People & Blogs
      ),
      status: Google::Apis::YoutubeV3::VideoStatus.new(
        privacy_status: 'public',
        self_declared_made_for_kids: false
      )
    )

    @youtube.insert_video('snippet,status', video, 
                          upload_source: @video_path, content_type: 'video/*') do |res, err|
      if err
        puts "Error uploading video: #{err}"
      else
        puts "Video uploaded with ID: #{res.id}"
      end
    end
  end
end

