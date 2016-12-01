require 'sinatra'
require 'sinatra/reloader'
require 'sinatra/content_for'
require 'erubis'
require 'rack'

root = File.expand_path("..", __FILE__)

get '/' do
  @docs = Dir.glob(root + "/data/*.txt").map { |file| File.basename file }
  erb :home
end

get '/:file_name' do
  file_path = root + "/data/" + params[:file_name]

  headers["Content-Type"] = "text/plain"
  File.read(file_path)
end
