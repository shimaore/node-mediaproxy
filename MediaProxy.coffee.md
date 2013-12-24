SingleMediaProxy forwards UDP packets in one direction.

    dgram = require 'dgram'
    assert = require 'assert'
    {EventEmitter} = require 'events'
    {log} = require 'util'

    class SingleMediaProxy extends EventEmitter

      constructor: (@local, @remote) ->

        assert @local?, 'local is required'
        assert @local?.port?, 'local.port is required'

        @sent = 0
        @received = 0
        @errors = 0

        @local.socket = dgram.createSocket 'udp4'

        @local.socket.on 'error', (err) =>
          log "Received error #{err} on port #{@local.port}"
          @emit 'error', err

        @local.socket.on 'message', (msg,rinfo) =>
          @received += 1
          # log "Received message on port #{@local.port}"
          @remote ?= rinfo
          @emit 'message', msg, rinfo
          # TODO: add jitter measure
          @renew_timeout()

Bind on the specified interface if applicable.

        if @local.address? and @local.address isnt '0.0.0.0' and @local.address isnt '::'
          @local.socket.bind @local.port, @local.address

Otherwise bind on all interfaces.

        else
          @local.socket.bind @local.port, =>
            @local.address = @local.socket.address()

        @renew_timeout()
        log "SingleMediaProxy ready on port #{@local.port}"
        return

      close: ->
        @local.socket.close()
        delete @local.socket
        if @local.timeout?
          clearTimeout @local.timeout
          delete @local.timeout
        log "SingleMediaProxy closed on port #{@local.port}"
        return

      send: (buf) ->
        if not @local.socket?
          log 'Not ready to send, no local socket.'
          return

        if @local.socket? and @remote? and @remote.address? and @remote.port?
          # log "Sending message out to #{@remote.address}:#{@remote.port}"
          @local.socket.send buf, 0, buf.length, @remote.port, @remote.address, (err,bytes) =>
            if err?
              @errors += 1
              log "Send failed with #{err}"
            else
              @sent += 1
        else
          log 'Not ready to send, still missing remote address or port'
        @renew_timeout()
        return

      renew_timeout: ->
        if @local.timeout?
          clearTimeout @local.timeout
        @local.timeout = setTimeout (=> @emit 'timeout'), 30000
        return


MediaProxy forwards UDP packets in both directions.

    module.exports = class MediaProxy

      constructor: (@config) ->
        @config ?= {}
        @config.ports ?= {}
        @config.ports.min ?= 49152
        @config.ports.max ?= 65535
        @config.ports.span = Math.floor (@config.ports.max - @config.ports.min) / 2

        @by_uuid = {}
        @by_port = {}

      allocate_port: ->
        port = @config.ports.min + 2 * Math.floor @config.ports.span * Math.random()
        while @by_port[port]?
          port += 2
          if port >= @config.ports.max
            return false
        return port

      allocate_proxy: (leg,linfo) ->
        leg.local ?=
          address: linfo.address ? @config.address
          port: linfo.port or @allocate_port()
        if not leg.local.port
          log 'Could not allocate a local port.'
          leg.error = 'Could not allocate a local port.'
          return
        delete leg.error
        leg.proxy = new SingleMediaProxy leg.local, leg.remote
        @by_port[leg.local.port] = leg
        log 'Allocate proxy successful'
        return

      remove_leg: (port) ->
        leg = @by_port[port]
        unless leg?
          log "Did not find a leg for port #{port}"
          return false
        name = leg.name
        uuid = leg.uuid
        leg.proxy?.close()
        delete leg.proxy
        delete @by_port[port]
        log "Removed leg #{name} uuid #{uuid}"
        return true

      add: (uuid,new_legs) ->

        @by_uuid[uuid] ?= {}
        legs = @by_uuid[uuid]

        for name, new_leg of new_legs
          do (name,new_leg) =>
            log "Updating leg #{name} in uuid #{uuid}"
            leg = legs[name] ? {}
            leg.name = name
            leg.uuid = uuid
            leg.remote ?= new_leg.remote
            unless leg.local?
              if new_leg.local?
                @allocate_proxy leg, new_leg.local
              leg.proxy?.on 'message', (msg) =>
                # log "Received message on uuid #{uuid} leg #{name}."
                # Dispatch.
                for n,l of legs when n isnt name
                  do (l) ->
                    l.proxy?.send msg
              leg.proxy?.on 'timeout', =>
                log "Received timeout on uuid #{uuid} leg #{name}."
                # Close the ports.
                @remove uuid
            legs[name] = leg
        log "Add successful for uuid #{uuid}"

      get: (uuid) ->
        response = {}
        legs = @by_uuid[uuid] ? {}
        for name,_ of legs
          response[name] =
            error: _.error
            remote:
              address: _.remote?.address
              port: _.remote?.port
            local:
              address: _.local?.address
              port: _.local?.port
            sent: _.proxy?.sent
            received: _.proxy?.received
            errors: _.proxy?.errors

        return response

      remove: (uuid) ->
        legs = @by_uuid[uuid]
        unless legs?
          log "Could not find legs for uuid #{uuid}"
          return error:"Could not find legs for uuid #{uuid}"
        for name,leg of legs
          if leg.local?
            @remove_leg leg.local.port
        delete @by_uuid[uuid]
        log "Removed uuid #{uuid}"
        return ok:true

      close: ->
        for uuid of @by_uuid
          @remove uuid
        delete @by_uuid
        delete @by_port
        log "Closed"
        return
