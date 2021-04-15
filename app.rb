require 'sinatra'
require 'bandwidth'

include Bandwidth
include Bandwidth::Voice

begin
    BW_USERNAME = ENV.fetch('BW_USERNAME')
    BW_PASSWORD = ENV.fetch('BW_PASSWORD')
    BW_ACCOUNT_ID = ENV.fetch('BW_ACCOUNT_ID')
    BW_VOICE_APPLICATION_ID = ENV.fetch('BW_VOICE_APPLICATION_ID')
    LOCAL_PORT = ENV.fetch('LOCAL_PORT')
    BASE_CALLBACK_URL = ENV.fetch('BASE_CALLBACK_URL')
rescue
    puts "Please set the environmental variables defined in the README"
    exit(-1)
end

set :port, LOCAL_PORT

bandwidth_client = Bandwidth::Client.new(
    voice_basic_auth_user_name: BW_USERNAME,
    voice_basic_auth_password: BW_PASSWORD
)
voice_client = bandwidth_client.voice_client.client

ACTIVE_CALLS = []

post '/callbacks/inbound' do
    callback_data = JSON.parse(request.body.read)

    if callback_data['eventType'] == 'initiate'
        ACTIVE_CALLS.append(callback_data['callId'])
    end

    response = Bandwidth::Voice::Response.new()
    if callback_data['eventType'] == 'initiate' or callback_data['eventType'] == 'redirect'
        ring = Bandwidth::Voice::Ring.new({
            :duration => 30
        })
        redirect = Bandwidth::Voice::Redirect.new({
            :redirect_url => '/callbacks/inbound'
        })

        response.push(ring)
        response.push(redirect)
    end

    return response.to_bxml()
end

post '/callbacks/goodbye' do
    callback_data = JSON.parse(request.body.read)
    
    response = Bandwidth::Voice::Response.new()
    if callback_data['eventType'] == 'redirect'
        speak_sentence = Bandwidth::Voice::SpeakSentence.new({
            :sentence => "The call has been updated. Goodbye"
        })
        response.push(speak_sentence)
    end

    return response.to_bxml()
end

delete '/calls/:call_id' do
    call_id = params[:call_id]

    if ACTIVE_CALLS.include?(call_id)
        body = ApiModifyCallRequest.new
        body.redirect_url = BASE_CALLBACK_URL + "/callbacks/goodbye"
        voice_client.modify_call(BW_ACCOUNT_ID, call_id, :body => body)

        ACTIVE_CALLS.delete(call_id)
        return 'deleted %s' % [call_id]
    else
        status 404
        return 'call not found'
    end
end

get '/activeCalls' do
    return ACTIVE_CALLS.to_json()
end
