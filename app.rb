require 'date'
require 'sinatra'
require 'plaid'
require './lib/alexa/request'
require './lib/alexa/response'

ACCESS_TOKEN = ENV['CHASE_ACCESS_TOKEN']

OMIT_ACCOUNTS = ['4V9AoqYZ35hX95eMbMmmFp0m74oDDESDo6O5j']
OMIT_CATEGORIES = ['Transfer', 'Credit Card', 'Deposit', 'Payment']

get '/' do
  erb :index
end

post '/' do
  alexa_request = Alexa::Request.new(request)

  name = alexa_request.slot_value("Name")
  month = alexa_request.slot_value("Date")

  return Alexa::Response.build('Please specify a month, like How much does Drew owe for July?') unless month =~ /^(?:[1-9]\d{3}-(?:0[1-9]|1[0-2]))$/

  transactions = fetch_transactions(first_day_of_month(month), last_day_of_month(month))
  total = transactions.sum {|t| t['amount'] }
  
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
  exchange_token_response = plaid_client.item.public_token.exchange(params['public_token'])
  access_token = exchange_token_response['access_token']
  item_id = exchange_token_response['item_id']
  puts "access token: #{access_token}"
  puts "item id: #{item_id}"
  exchange_token_response.to_json
end

private

def clean_transactions(transactions)
  transactions.reject do |t|
    (OMIT_CATEGORIES.include?(t['category'][0]) unless t['category'].to_a.empty?) || (OMIT_ACCOUNTS.include?(t['account_id']))
  end
end

def fetch_transactions(start_date, end_date)
  transaction_response = plaid_client.transactions.get(ACCESS_TOKEN, start_date, end_date)
  transactions = transaction_response['transactions']
end

def fetch_paginated_transactions(transactions, start_date, end_date)
  while transactions.length < transaction_response['total_transactions']
    transaction_response = plaid_client.transactions.get(ACCESS_TOKEN, start_date, end_date, offset: transactions.length)
    transactions += transaction_response['transactions']
  end
end

def first_day_of_month
  Date.parse "#{month}-01"
end

def last_day_of_month
  Date.civil(start_date.year, start_date.month, -1)
end

def plaid_client
  Plaid::Client.new(env: :development, client_id: ENV['PLAID_CLIENT_ID'], secret: ENV['PLAID_SECRET'], public_key: ENV['PLAID_PUBLIC_KEY'])
end
