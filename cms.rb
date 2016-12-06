require 'sinatra'
require 'sinatra/reloader'
require 'sinatra/content_for'
require 'tilt/erubis'
require 'rack'
require 'redcarpet'
require 'yaml'
require 'bcrypt'
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
  if %w(.jpg .png).include? File.extname(file)
    send_file File.join(file)
  elsif
    contents = File.read(file)
    case File.extname(file)
    when ".md"
      erb markdown_to_html(contents)
    when '.txt'
      headers["Content-Type"] = "text/plain"
      contents
    end
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

get '/img' do
  erb :img_upload
end

get '/users/signup' do
  erb :signup
end

get '/users/signin' do
  erb :signin
end

get '/new' do
  verify_login

  erb :new_file
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

get '/:file_name' do
  file_name, file_path = get_file_and_filepath(params[:file_name], data_path)
  if File.exist? file_path
    load_contents(file_path)
  else
    nonexistant_file(file_name)
  end
end

post '/img' do
  filename = params[:img_file][:filename]
  image_file = params[:img_file][:tempfile]
  if params[:img_file].empty?
    session[:message] = "Please choose an image."
    erb :img_upload
  elsif !%w(.jpg .png).include? File.extname(filename)
    session[:message] = "Unsupported file type."
    erb :img_upload
  else
    file_path = File.join(data_path, filename)
    File.open(file_path, 'wb') do |file|
      file.write(File.read(image_file))
    end
    session[:message] = "#{filename} was created."
    redirect '/'
  end
end

def correct_login?(user, password)
  users = load_user_credentials
  if users.key? user
    BCrypt::Password.new(users[user]) == password
  else
    false
  end
end

post "/users/signin" do
  username = params[:username]
  password = params[:password]
  if correct_login?(username, password)
    session[:username] = username
    session[:message] = 'Welcome!'
    redirect '/'
  else
    session[:message] = 'Invalid Credentials'
    erb :signin
  end
end

def valid_user?(user)
  users = load_user_credentials
  !users.key?(user) && !user.empty?
end

def valid_password?(password, confirm_password)
  (password == confirm_password) && !password.empty? && (password.size > 6)
end

post "/users/signup" do
  username = params[:username]
  password = params[:password]
  confirm = params[:con_password]

  if !valid_user?(username)
    session[:message] = "Username is either taken or empty."
    erb :signup
  elsif !valid_password?(password, confirm)
    session[:message] = "Passwords either don't match or are too short."
    erb :signup
  elsif valid_user?(username) && valid_password?(password, confirm)
    File.open('users.yml', 'a') do |file|
      file.write (username + ': ' + BCrypt::Password.create(password))
    end
    session[:message] = "#{username} was created. Please login."
    redirect '/users/signin'
  end
end

post "/users/signout" do
  session[:username] = nil
  session[:message] = "You have been logged out."
  redirect "/users/signin"
end

post '/create' do
  verify_login

  doc_name = params[:new_file].strip
  extension = File.extname(doc_name)
  if doc_name.empty?
    session[:message] = "Please enter a document name."
    status 422
    erb :new_file
  elsif extension.empty?
    session[:message] = "Please include an extension."
    status 422
    erb :new_file
  elsif !%w(.md .txt).include? extension
    session[:message] = "Only .md and .txt extensions are supported."
    status 422
    erb :new_file
  else
    File.write(File.join(data_path, doc_name), '')

    session[:message] = "#{doc_name} was created."
    redirect "/"
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

post "/:file_name/duplicate" do
  verify_login

  file_name, file_path = get_file_and_filepath(params[:file_name], data_path)
  contents = File.read(file_path)
  ext = File.extname(file_name)
  new_file = file_name.gsub(ext, '') + "_copy" + ext

  File.open(File.join(data_path, new_file), "w+") { |file| file.write contents }

  session[:message] = "#{file_name} was duplicated."
  redirect "/"
end
