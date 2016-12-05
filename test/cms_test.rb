ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require "fileutils"

require_relative "../cms"

class CMSTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def session
    last_request.env["rack.session"]
  end

  def admin_signin
    {"rack.session" => {username: "admin"}}
  end

  def setup
    FileUtils.mkdir_p(data_path)
  end

  def teardown
    FileUtils.rm_rf(data_path)
  end

  def create_document(name, content = "")
    File.open(File.join(data_path, name), 'w') do |file|
      file.write(content)
    end
  end

  def test_index
    create_document "example.md"
    create_document "about.txt"

    get "/", {}, admin_signin
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "about.txt"
    assert_includes last_response.body, "example.md"
    assert_includes last_response.body, "New Document"
  end

  def test_text_files
    response = <<~TEXT
    1993 - Yukihiro Matsumoto dreams up Ruby.
    1995 - Ruby 0.95 released.
    1996 - Ruby 1.0 released.
    1998 - Ruby 1.2 released.
    1999 - Ruby 1.4 released.
    2000 - Ruby 1.6 released.
    2003 - Ruby 1.8 released.
    2007 - Ruby 1.9 released.
    2013 - Ruby 2.0 released.
    2013 - Ruby 2.1 released.
    2014 - Ruby 2.2 released.
    2015 - Ruby 2.3 released.
    TEXT

    create_document("history.txt", response)

    get "/history.txt"
    assert_equal 200, last_response.status
    assert_equal "text/plain", last_response["Content-Type"]
    assert_includes last_response.body, "2015 - Ruby 2.3 released."
    assert_equal "329", last_response["Content-Length"]
  end

  def test_nonexistant_file
    get "/blah.txt", {}, admin_signin
    assert_equal 302, last_response.status
    assert_equal "blah.txt does not exist.", session[:message]
  end

  def test_markdown
    create_document 'example.md', "<h1>An h1 header</h1>"

    get '/example.md'
    assert_equal 200, last_response.status
    assert_includes last_response.body, "<h1>An h1 header</h1>"
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
  end

  def test_edit_page
    create_document 'about.txt', "Edit content of about.txt:"

    get '/about.txt/edit', {}, admin_signin
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Edit content of about.txt:"
  end

  def test_changing_files
    create_document 'about.txt'

    post '/about.txt', {file_contents: "Hello World"}, admin_signin
    assert_equal 302, last_response.status
    assert_equal "about.txt has been updated.", session[:message]

    get '/about.txt'
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Hello World"
  end

  def test_new_file_form
    get '/new', {}, admin_signin
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Add a new document:"
  end

  def test_create_new_file

    post '/create', {new_file: 'story.md'}, admin_signin
    assert_equal 302, last_response.status
    assert_equal "story.md was created.", session[:message]

    get '/'
    assert_includes last_response.body, 'story.md'
  end

  def test_create_file_without_name
    post '/create', {new_file: ''}, admin_signin
    assert_equal 422, last_response.status
    assert_includes last_response.body, "Please enter a document name."
  end

  def test_create_file_without_extension
    post '/create', {new_file: 'ruby'}, admin_signin
    assert_equal 422, last_response.status
    assert_includes last_response.body, "Please include an extension."
  end

  def test_delete_file
    create_document 'test.txt'

    post "/test.txt/destroy", {}, admin_signin
    assert_equal 302, last_response.status
    assert_equal "test.txt was deleted.", session[:message]

    get last_response["Location"]

    get '/'
    refute_includes last_response.body, 'test.txt'
  end

  def test_redirect_if_loggedoff
    get '/'
    assert_equal 302, last_response.status

    get last_response["Location"]
    assert_includes last_response.body, 'Username'
  end

  def test_signin_form
    get '/users/signin'
    assert_equal 200, last_response.status
    assert_includes last_response.body, 'Username'
  end

  def test_invalid_login
    post '/users/signin', username: "foo", password: "bar"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Invalid Credentials"
  end

  def test_successful_login
    post '/users/signin', username: "admin", password: "secret"
    assert_equal 302, last_response.status
    assert_equal "Welcome!", session[:message]
  end

  def test_logout
    post "/users/signout", {}, admin_signin
    assert_equal 302, last_response.status
    assert_equal "You have been logged out.", session[:message]

    get last_response["Location"]
    assert_includes last_response.body, "Username:"
  end
end
