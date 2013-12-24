SingleMediaProxy forwards UDP packets in one direction.

    dgram = require 'dgram'
    assert = require 'assert'
    {EventEmitter} = require 'events'

    class SingleMediaProxy extends EventEmitter

      constructor: (@local, @remote) ->

        assert @local?, 'local is required'
        assert @local?.port? 'local.port is required'

        @local.socket = dgram.createSocket 'udp4'

        @local.socket.on 'message', (msg,rinfo) ->
          @remote ?= rinfo
          @emit 'message', msg, rinfo

Bind on the specified interface if applicable.

        if @local.address? and @local.address isnt '0.0.0.0' and @local.address isnt '::'
          @local.socket.bind @local.port, @local.address

Otherwise bind on all interfaces.

        else
          @local.socket.bind @local.port, ->
            @local.address = @local.socket.address()

      close: ->
        @local.socket.close()
        delete @local.socket

      send: (buf,cb) ->
        if @remote? and @remote.address? and @remote.port?
          @local.socket.send buf, 0, buf.length, @remote.port, @remote.address, (err,bytes) ->
            cb? err, bytes
        else
          cb? 'Not ready'

MediaProxy forwards UDP packets in both directions.

    class MediaProxy

      by_uuid: {}
      by_port: {}

      constructor: (@config) ->
        @config ?= {}
        @config.ports ?= {}
        @config.ports.min ?= 49152
        @config.ports.max ?= 65535
        @config.ports.span = Math.floor (@config.ports.max - @config.ports.min) / 2

      allocate_port: ->
        port = @config.ports.min + 2 * Math.floor @config.ports.span * Math.random()
        while by_port[port]?
          port += 2
          if port >= @config.ports.max
            return false
        return port

      allocate_proxy: (leg) ->
        leg.local ?=
          address: @config.local?.address
          port: allocate_port()
        if not leg.local.port
          return false
        leg.proxy = new SingleMediaProxy leg.local, leg.remote
        by_port[leg.local.port] = leg
        leg

      remove_leg: (port) ->
        leg = by_port[port]
        return false unless leg?
        leg.proxy?.close()
        delete leg.proxy
        delete by_port[port]
        return true

      add: (uuid,legs) ->
        by_uuid[uuid] ?= {}
        for k,v of legs
          v.uuid = uuid
          @allocate_proxy v
          if not v
            return false
          v.proxy.on 'message', (msg) ->
            for l,w of legs when l isnt k
              w.proxy?.send msg
          by_uuid[uuid][k] = v

      remove: (uuid) ->
        legs = by_uuid[uuid]
        return false unless legs?
        for k,v of legs
          @remove_leg v.local.port
        delete by_uuid[uuid]
        return true
