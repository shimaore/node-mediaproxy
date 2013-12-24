Basic test for mediaproxy
=========================

Create the mediaproxy service

    should = require 'should'

    config =
      service:
        port: 25060
        host: '127.0.0.1'
      media:
        ports: {}
        address: '127.0.0.1'

    mediaproxy = require '../index'

    mediaproxy config

Create a first leg on a defined port on the loopback address.

    test = ->

      expected_number_of_packets = 42

      request = require 'superagent'

      id = 'id' + 10000*Math.random()
      id_url = "http://#{config.service.host}:#{config.service.port}/proxy/#{id}"

      port = 45632

      step1 = (next) ->
        console.log 'Step 1'
        request.
          put(id_url).
          send(
            first_leg:
              local:
                port: port              # Force-bind to this port
          ).
          type('json').
          end (err,res) ->
            should.not.exist err
            res.body.should.have.property 'first_leg'
            res.body.first_leg.should.not.have.property 'error'
            do next

Start a UDP receiver on a random port.

      dgram = require 'dgram'

      receiver_port = Math.floor 54000 + 452 * Math.random()

      step2 = (next) ->
        console.log 'Step 2'
        receiver = dgram.createSocket 'udp4'

        counter = 0

        receiver.on 'message', (msg,rinfo) ->
          data = JSON.parse msg
          data.should.have.property('i')
          data.i.should.be.a.Number
          console.log "Received message ##{data.i} from #{rinfo.address}:#{rinfo.port}"
          counter += 1
          if counter is expected_number_of_packets
            request.post("http://#{config.service.host}:#{config.service.port}/proxy/shutdown").end ->
              console.log 'Shutting down'
              receiver.close()

        receiver.bind receiver_port

Create a second leg on a defined port on the loopback address, with the remote set to the UDP receiver's port.

        request.
          put(id_url).
          send(
            second_leg:
              local:
                port: null            # any falsey value will lead to auto-allocation
              remote:
                address: '127.0.0.1'
                port: receiver_port
          ).
          end (err,res) ->
            should.not.exist err
            res.body.should.have.property 'second_leg'
            res.body.second_leg.should.not.have.property 'error'
            do next

Start a UDP sender on a random port.

      step3 = (next) ->
        console.log 'Step 3'
        sender = dgram.createSocket 'udp4'

Verify that trafic send by the sender is received by the receiver.

        counter = 0

        for i in [1..expected_number_of_packets]
          do (i) ->
            buf = new Buffer JSON.stringify {i}
            sender.send buf, 0, buf.length, port, '127.0.0.1', ->
              counter += 1
              console.log "Sent #{counter} packets."
              if counter is expected_number_of_packets
                sender.close()
                do next

      step1 -> step2 -> step3 -> console.log 'Waiting'

    setTimeout test, 1000
