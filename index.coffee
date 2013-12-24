MediaProxy = require './MediaProxy'
zappajs = require 'zappajs'

module.exports = (config) ->

  zappajs ->

    mediaproxy = new MediaProxy config

    @use 'bodyparser'

    # The `body` is a hash of `{local,remote}` entries (remotes are optional) where
    # each of `local` or `remote` is `{address,port}`.
    # Normally two legs are present ('a' leg and 'b' leg) but the proxy supports
    # media duplication (e.g. for storage or diffusion) so additional (silent) legs
    # may be present.
    # This method also supports adding legs (e.g. starting only with a 'a' leg and
    # adding the 'b' leg at a later time).

    @put '/proxy/:uuid': ->
      if mediaproxy.add @req.param.uuid, @req.body
        @json ok:true
      else
        @json error:'failed'

    @get '/proxy/:uuid', ->
      @json mediaproxy.by_uuid[@req.param.uuid]

    @delete '/proxy/:uuid': ->
      if mediaproxy.remove @req.param.uuid
        @json ok:true
      else
        @json error:'failed'
