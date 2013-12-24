MediaProxy = require './MediaProxy'
zappajs = require 'zappajs'

module.exports = (config) ->

  service = config.service ? {}
  service.disable_io = true

  zappajs config.service, ->

    mediaproxy = new MediaProxy config.media

    @use 'bodyParser'

    # The `body` is a hash of `{local,remote}` entries (remotes are optional) where
    # each of `local` or `remote` is `{address,port}`.
    # Normally two legs are present ('a' leg and 'b' leg) but the proxy supports
    # media duplication (e.g. for storage or diffusion) so additional (silent) legs
    # may be present.
    # This method also supports adding legs (e.g. starting only with a 'a' leg and
    # adding the 'b' leg at a later time).

    @put '/proxy/:uuid', ->
      mediaproxy.add @req.params.uuid, @req.body
      @json mediaproxy.get @req.params.uuid

    @get '/proxy/:uuid', ->
      @json mediaproxy.get @req.params.uuid

    @delete '/proxy/:uuid', ->
      @json if mediaproxy.remove @req.params.uuid

    server = @server

    @post '/proxy/shutdown', ->
      server.close()
      mediaproxy.close()
      @json ok:true
