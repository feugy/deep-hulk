Player = require 'hyperion/model/Player'
PlayerService = require('hyperion/service/PlayerService').get()
Item = require 'hyperion/model/Item'
TurnRule = require 'hyperion/model/TurnRule'
ClientConf = require 'hyperion/model/ClientConf'

# Sends a notification to players that needs to play
class WarnNotifRule extends TurnRule

 
  # Selects squads that were not notified, that have not ended their turn and :
  # - squad that are not waiting for deployment and that are active
  # - squad that are not waiting for deployement in rush games
  # - alien squads that are in deployement
  #
  # @param callback [Function] called when the rule is applied, with two arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback targets [Array] list of targeted object, null or empty if the rule does not apply.
  select: (callback) =>
    Item.find {type: 'squad', notified: false, turnEnded: false}, (err, squads) =>
      return callback err if err?
      callback null, (
        for squad in squads when (squad.activeSquad in [null, squad.name] and not squad.deployZone?) or 
            (squad.isAlien and squad.deployZone?)
          squad
      )

  # Get squad's player, and if he did not connect in the previous 6 hours, send
  # him a notification.
  #
  # @param squad [Object] the targeted squad
  # @param callback [Function] called when the rule is applied, with arguments:
  # @option callback err [String] error string. Null if no error occured
  execute: (squad, callback) =>
    # get squad's player
    Player.findOne {email:squad.player}, (err, player) =>
      return callback err if err?
      connected = -1 isnt PlayerService.connectedList.indexOf player.email
      # only if not connected and absent for more than 3 hours
      return callback null if connected or (Date.now() - player.lastConnection.getTime()) <= 3*60*60*1000
      # get game
      id = squad.id[squad.id.indexOf('-')+1...squad.id.lastIndexOf '-']
      Item.findCached ["game-#{id}"], (err, [game]) =>
        return callback err if err?
        ClientConf.findCached ['default'], (err, [conf]) =>
          return callback err if err?
          # to avoid multiple notifications
          squad.notified = true
          console.log "send notification to #{player.email} on game #{game.name}"
          # send a notification
          @sendCampaign
            players: player
            msg: """[Deep Hulk][#{game.name}] #{player.firstName}, vos adversaires vous attendent !
<p>Bonjour #{player.firstName} !</p>
<p>Vous pouvez jouer vos <b>#{conf.values.labels[squad.name]}</b> dans <i>#{game.name}</i>.</p>
<p>Rendez vous sans tarder sur <a href="http://mythic-forge.com/game/board?id=#{game.id}">Deep into the Hulk!</a></p>
<br/>
<p>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;-- la Myth'team</p>
"""
          callback null
  
module.exports = new WarnNotifRule 20