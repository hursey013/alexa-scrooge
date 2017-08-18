require 'date'
require 'plaid'
require 'sinatra'

require './lib/alexa/request'
require './lib/alexa/response'

set :public_folder, File.dirname(__FILE__) + '/public'

client = Plaid::Client.new(env: :development,
                           client_id: ENV['PLAID_CLIENT_ID'],
                           secret: ENV['PLAID_SECRET'],
                           public_key: ENV['PLAID_PUBLIC_KEY'])

ACCESS_TOKEN = ENV['CHASE_ACCESS_TOKEN']

OMIT_ACCOUNTS = ['4V9AoqYZ35hX95eMbMmmFp0m74oDDESDo6O5j']
OMIT_CATEGORIES = ['Transfer', 'Credit Card', 'Deposit', 'Payment']

get '/' do
  erb :index
end

post '/' do
  alexa_request = Alexa::Request.new(request)

  name = alexa_request.slot_value("Name")
  total = fetch_transactions.sum {|t| t['amount'] }
  
  if name.nil? 
    message = "Collectively, you've spent $#{total.round(2)} from #{start_date} to #{end_date}"
  else
    message = "If specifying a person, use only Brian or Drew"
    name = name.downcase

    if name == 'brian'
      message = "Brian, you owe $#{(total.to_f * 0.6).round(2)} for #{start_date} to #{end_date}"
    elsif name == 'drew'
      message = "Drew, you owe $#{(total.to_f * 0.4).round(2)} for #{start_date} to #{end_date}"
    end
  end
  
  return Alexa::Response.build(message)
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

def fetch_transactions
  today = Date.today

  if today.day <= 15
    start_date = Date.parse "#{today.year}-#{today.month}-01"
    end_date = Date.parse "#{today.year}-#{today.month}-15"
  else
    start_date = Date.parse "#{today.year}-#{today.month}-15"
    end_date = Date.civil(today.year, today.month, -1)  
  end
  
  begin
    transactions_response = client.transactions.get(ACCESS_TOKEN, start_date, end_date)
  rescue Plaid::ItemError => e
    return Alexa::Response.build(e.error_message)
  end
  
  transactions = transaction_response['transactions']  
  
  while transactions.length < transaction_response['total_transactions']
    transaction_response = client.transactions.get(ACCESS_TOKEN, start_date, end_date, offset: transactions.length)
    transactions += transaction_response['transactions']
  end
  
  transactions.reject do |t|
    (OMIT_CATEGORIES.include?(t['category'][0]) unless t['category'].to_a.empty?) || (OMIT_ACCOUNTS.include?(t['account_id']))
  end
end
