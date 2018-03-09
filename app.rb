require 'date'
require 'plaid'
require 'sinatra'
require './lib/alexa/request'
require './lib/alexa/response'

set :public_folder, File.dirname(__FILE__) + '/public'

OMIT_ACCOUNTS = [].freeze
OMIT_CATEGORIES = [ 'Transfer', 'Credit', 'Deposit', 'Payment' ].freeze
ACCOUNTS = ENV['ACCESS_TOKENS'].split(' ').freeze
USERS = [ { name: 'Brian', percentage: 0.6 }, { name: 'Drew', percentage: 0.4 }].freeze

get '/' do
  erb :index
end

post '/' do
  alexa_request = Alexa::Request.new(request)
  name = alexa_request.slot_value("Name")
  
  today = Date.today

  if today.day >= 3 && today.day <= 18
    start_date = Date.parse "#{today.year}-#{today.month}-01"
    end_date = Date.parse "#{today.year}-#{today.month}-15"
  else
    start_date = Date.parse "#{today.year}-#{today.month}-15"
    end_date = Date.civil(today.year, today.month, -1)  
  end

  total = 0
  
  ACCOUNTS.each do |account|
    total += fetch_transactions(start_date, end_date, account).sum {|t| t['amount'] }
  end

  message = "Collectively, you've spent $#{total.round(2)} from #{start_date} to #{end_date}"
  
  return Alexa::Response.build(message) if name.nil?

  USERS.each do |user|
    if name.downcase == user[:name].downcase
      message = "#{user[:name]}, you owe $#{(total.to_f * user[:percentage]).round(2)} for #{start_date} to #{end_date}"
    end
  end

  Alexa::Response.build(message)
end

post '/get_access_token' do
  exchange_token_response = client.item.public_token.exchange(params['public_token'])
  access_token = exchange_token_response['access_token']
  item_id = exchange_token_response['item_id']
  puts "access token: #{access_token}"
  puts "item id: #{item_id}"
  exchange_token_response.to_json
end

private

def client
  Plaid::Client.new(
    env: :development,
    client_id: ENV['PLAID_CLIENT_ID'],
    secret: ENV['PLAID_SECRET'],
    public_key: ENV['PLAID_PUBLIC_KEY']
  )
end

def fetch_transactions(start_date, end_date, account)
  begin
    transaction_response = client.transactions.get(account, start_date, end_date)
  rescue Plaid::ItemError => e
    return Alexa::Response.build(e.error_message)
  end
  
  puts transaction_response
  
  transactions = transaction_response['transactions']  
  
  while transactions.length < transaction_response['total_transactions']
    transaction_response = plaid_client.transactions.get(account, start_date, end_date, offset: transactions.length)
    transactions += transaction_response['transactions']
  end
  
  transactions.reject do |t|
    (OMIT_CATEGORIES.include?(t['category'][0]) unless t['category'].to_a.empty?) || (OMIT_ACCOUNTS.include?(t['account_id']))
  end
end
