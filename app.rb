require 'sinatra'
require 'bandwidth-sdk'

begin
  BW_USERNAME = ENV.fetch('BW_USERNAME')
  BW_PASSWORD = ENV.fetch('BW_PASSWORD')
  BW_ACCOUNT_ID = ENV.fetch('BW_ACCOUNT_ID')
  BW_VOICE_APPLICATION_ID = ENV.fetch('BW_VOICE_APPLICATION_ID')
  LOCAL_PORT = ENV.fetch('LOCAL_PORT')
  BASE_CALLBACK_URL = ENV.fetch('BASE_CALLBACK_URL')
rescue StandardError
  puts 'Please set the environmental variables defined in the README'
  exit(-1)
end

set :port, LOCAL_PORT

Bandwidth.configure do |config| # Configure Basic Auth
  config.username = BW_USERNAME
  config.password = BW_PASSWORD
end
set :port, LOCAL_PORT

$active_calls = []

post '/callbacks/inboundCall' do
  data = JSON.parse(request.body.read)

  $active_calls << data['callId'] if data['eventType'] == 'initiate'

  if (data['eventType'] == 'initiate') || (data['eventType'] == 'redirect')
    speak_sentence = Bandwidth::Bxml::SpeakSentence.new('Redirecting call, please wait.')
    ring = Bandwidth::Bxml::Ring.new({ duration: 30 })
    redirect = Bandwidth::Bxml::Redirect.new({ redirect_url: '/callbacks/inboundCall' })
    response = Bandwidth::Bxml::Response.new([speak_sentence, ring, redirect])

    return response.to_bxml
  end
end

post '/callbacks/callEnded' do
  data = JSON.parse(request.body.read)

  if data['eventType'] == 'redirect'
    speak_sentence = Bandwidth::Bxml::SpeakSentence.new('The call has been ended. Goodbye')
    response = Bandwidth::Bxml::Response.new([speak_sentence])
    
    return response.to_bxml
  end
end

delete '/calls/:call_id' do
  call_id = params[:call_id]
  
  if $active_calls.include?(call_id)
    call_body = Bandwidth::UpdateCall.new({ redirect_url: "#{BASE_CALLBACK_URL}/callbacks/callEnded" })
    
    calls_api_instance = Bandwidth::CallsApi.new
    calls_api_instance.update_call(BW_ACCOUNT_ID, call_id, call_body)
    $active_calls.delete(call_id)

    return "call #{call_id} will be ended"
  else
    status 404
    return 'call not found'
  end
end

get '/calls' do
  return $active_calls.to_json
end
