require 'sinatra'
require 'sinatra/reloader'
require 'sinatra/content_for'
require 'tilt/erubis'
require 'rack'
require 'redcarpet'
require 'bcrypt'
require 'yaml'
require 'pry'

configure do
  enable :sessions
  set :session_secret, 'super secret'
end

before do
  session[:username] ||= nil
end

def verify_login
  unless session[:username]
    session[:message] = "You must login."
    redirect "/users/signin"
  end
end

def data_path
  if ENV["RACK_ENV"] == 'test'
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def load_user_credentials
  credentials = if ENV["RACK_ENV"] == 'test'
    File.expand_path("../test/users.yml", __FILE__)
  else
    File.expand_path("../users.yml", __FILE__)
  end
  YAML.load_file(credentials)
end

def markdown_to_html(text)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(text)
end

def load_contents(file)
  contents = File.read(file)
  case File.extname(file)
  when ".md"
    erb markdown_to_html(contents)
  when '.txt'
    headers["Content-Type"] = "text/plain"
    contents
  end
end

def get_file_and_filepath(file, data_path)
  file_path = File.join(data_path, file)
  [file, file_path]
end

def nonexistant_file(file)
  session[:message] = "#{file} does not exist."
  redirect "/"
end

get '/' do
  verify_login

  pattern = File.join(data_path, "*")
  @docs = Dir.glob(pattern).map { |file| File.basename file }
  erb :home
end

def correct_login?(users, user, password)
  users[user] == password
end

post "/users/signin" do
  users = load_user_credentials

  username = params[:username]
  password = BCrypt::Password.create(params[:password])
  if correct_login?(users, username, password)
    session[:username] = username
    session[:message] = 'Welcome!'
    redirect '/'
  else
    session[:message] = 'Invalid Credentials'
    erb :signin
  end
end

post "/users/signout" do
  session[:username] = nil
  session[:message] = "You have been logged out."
  redirect "/users/signin"
end

get '/users/signin' do
  erb :signin
end

get '/new' do
  verify_login

  erb :new_file
end

post '/create' do
  verify_login

  doc_name = params[:new_file].strip
  if doc_name.empty?
    session[:message] = "Please enter a document name."
    status 422
    erb :new_file
  elsif File.extname(doc_name).empty?
    session[:message] = "Please include an extension."
    status 422
    erb :new_file
  else
    File.write(File.join(data_path, doc_name), '')

    session[:message] = "#{doc_name} was created."
    redirect "/"
  end
end

get '/:file_name' do
  file_name, file_path = get_file_and_filepath(params[:file_name], data_path)
  if File.exist? file_path
    load_contents(file_path)
  else
    nonexistant_file(file_name)
  end
end

get "/:file_name/edit" do
  verify_login

  @file, file_path = get_file_and_filepath(params[:file_name], data_path)
  if File.exist? file_path
    @contents = File.read(file_path)
    erb :file_edit
  else
    nonexistant_file(@file)
  end
end

post "/:file_name" do
  verify_login

  file_name, file_path = get_file_and_filepath(params[:file_name], data_path)

  contents = params[:file_contents]
  File.open(file_path, 'w') { |file| file.write contents }

  session[:message] = "#{file_name} has been updated."
  redirect '/'
end

post "/:file_name/destroy" do
  verify_login

  file_name, file_path = get_file_and_filepath(params[:file_name], data_path)
  File.delete(file_path)

  session[:message] = "#{file_name} was deleted."
  redirect "/"
end
