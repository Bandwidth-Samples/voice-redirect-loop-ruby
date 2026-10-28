require 'sinatra'
require 'bandwidth-sdk'

begin
  BW_ACCOUNT_ID = ENV.fetch('BW_ACCOUNT_ID')
  BW_CLIENT_ID = ENV.fetch('BW_CLIENT_ID')
  BW_CLIENT_SECRET = ENV.fetch('BW_CLIENT_SECRET')
  BASE_CALLBACK_URL = ENV.fetch('BASE_CALLBACK_URL')
  LOCAL_PORT = Integer(ENV.fetch('LOCAL_PORT'))
rescue StandardError
  puts 'Please set the environmental variables defined in the README'
  exit(-1)
end

set :port, LOCAL_PORT
set :host_authorization, permitted_hosts: []

Bandwidth.configure do |config|
  config.client_id = BW_CLIENT_ID
  config.client_secret = BW_CLIENT_SECRET
end

ACTIVE_CALLS = Set.new

def parse_body
  data = JSON.parse(request.body.read)
  halt 400 unless data.is_a?(Hash)
  data
rescue JSON::ParserError
  halt 400
end

post '/callbacks/inbound/voice' do
  data = parse_body
  halt 400 unless %w[initiate redirect].include?(data['eventType'])

  ACTIVE_CALLS << data['callId'] if data['eventType'] == 'initiate'

  speak_sentence = Bandwidth::Bxml::SpeakSentence.new('Redirecting call, please wait.')
  ring = Bandwidth::Bxml::Ring.new({ duration: 30 })
  redirect = Bandwidth::Bxml::Redirect.new({ redirect_url: '/callbacks/inbound/voice' })

  content_type 'application/xml'
  Bandwidth::Bxml::Response.new([speak_sentence, ring, redirect]).to_bxml
end

post '/callbacks/inbound/voice/callEnded' do
  data = parse_body
  halt 400 unless data['eventType'] == 'redirect'

  speak_sentence = Bandwidth::Bxml::SpeakSentence.new('The call has been ended. Goodbye.')
  hangup = Bandwidth::Bxml::Hangup.new

  content_type 'application/xml'
  Bandwidth::Bxml::Response.new([speak_sentence, hangup]).to_bxml
end

post '/callbacks/inbound/voice/disconnect' do
  data = parse_body
  halt 400 unless data['eventType'] == 'disconnect'

  ACTIVE_CALLS.delete(data['callId'])
  status 204
end

get '/calls' do
  content_type 'application/json'
  ACTIVE_CALLS.to_a.to_json
end

delete '/calls/:call_id' do
  call_id = params[:call_id]
  halt 404 unless ACTIVE_CALLS.include?(call_id)

  update_call = Bandwidth::UpdateCall.new(redirect_url: "#{BASE_CALLBACK_URL}/callbacks/inbound/voice/callEnded")

  begin
    Bandwidth::CallsApi.new.update_call(BW_ACCOUNT_ID, call_id, update_call)
  rescue StandardError => e
    warn "Failed to update call: #{e.message}"
    halt 500
  end

  ACTIVE_CALLS.delete(call_id)
  status 204
end
