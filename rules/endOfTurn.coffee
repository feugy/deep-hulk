_ = require 'underscore'
async = require 'async'
Rule = require 'hyperion/model/Rule'
Item = require 'hyperion/model/Item'
{moveCapacities, alienCapacities} = require './constants'
{hasSharedPosition, addAction, makeState} = require './common'

# When player has finished its turn, may trigger another turn
class EndOfTurnRule extends Rule

  # May apply only if remaining turn not already ended and no twist or deploy in progress
  # 
  # @param player [Player] the concerned player
  # @param squad [Item] the concerned squad
  # @param context [Object] extra information on resolution context
  # @param callback [Function] called when the rule is applied, with two arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback params [Array] array of awaited parameter (may be empty), or null/undefined if rule does not apply
  canExecute: (player, squad, context, callback) =>
    # inhibit if waiting for deployment
    return callback null, null if squad.deployZone? or squad.waitTwist
    return callback null, if squad.type.id is 'squad' and not squad.turnEnded then [] else null

  # Check other squad's remaining action. 
  # If possible, trigger next turn.
  #
  # @param player [Player] the concerned player
  # @param squad [Item] the concerned squad
  # @param params [Object] associative array (may be empty) of awaited parametes, specified by resolve.
  # @param context [Object] extra information on execution context
  # @param callback [Function] called when the rule is applied, with one arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback result [Object] an arbitrary result of this rule.
  execute: (player, squad, params, context, callback) =>
    squad.game.fetch (err, game) =>
      return callback err if err?
      # do not allow to pass if game is finished
      return callback "gameFinished" if game.finished
      # allow shared position to avoid deadlocks
      # return callback new Error 'sharedPosition' if hasSharedPosition squad.members
        
      for member in squad.members
        # check that dreadnought are not stuck under a door
        if member.kind is 'dreadnought' and member.revealed and member.underDoor
          return callback new Error 'underDoor'
        member.rcNum = 0
        member.ccNum = 0
        member.moves = 0
      
      # set to -1 to avoid same squad triggering multiple times end of turn
      squad.turnEnded = true
      console.log "end of turn #{game.turn} for squad #{squad.name}"
        
      process = =>
        # in single player mode, set next player as active
        if game.singleActive
          active = null
          for obj, i in game.players when obj.squad is squad.name
            # search for next squad that did not ended its turn
            for j in [i+1...game.players.length]
              active = game.players[j].squad
              break unless _.findWhere(game.squads, name: active).turnEnded
            break
          other.activeSquad = active for other in game.squads
        
        # quit a first squad that do not have ended its turn
        for other in game.squads when other.id isnt squad.id
          return callback null unless other.turnEnded
           
        # next turn ! in singl player mode, set first player as active
        if game.singleActive
          other.activeSquad = game.players[0].squad for other in game.squads
        
        # pick a twist from available ones
        if game.twists.length > 0
          idx = Math.floor Math.random()*game.twists.length
          twist = game.twists.splice(idx, 1)[0]
          waitTwist = true
        else 
          # TODO last turn !
          twist = null
          waitTwist = false
          
        # reset each squads for next turn
        async.each game.squads, (s, next) =>
          s.fetch (err, squad) =>
            # fetch squad to get members
            return next err if err?
            squad.firstAction = true
            
            if squad.isAlien
              # affect twist
              squad.twist = twist
              # reset number of blip to reinforce
              squad.supportBlips = 6 
            else
              # reset pending marine twist
              squad.twist = null
              
            # wait for twist resolution
            squad.waitTwist = waitTwist
            # reset number of blip to reveal
            squad.revealBlips = 3 if 'detector' in squad.equipment

            hasAlive = false
            # reset each member, unless not on map
            for member in squad.members when member.map? and not member.dead
              hasAlive = true
              # use first weapon to get allowed moves
              weapon = member.weapons[0]?.id or member.weapons[0]
              # add an attack
              member.rcNum = 1
              member.ccNum = 1
              member.usedWeapons = []
              # remove blinding grenade immunity
              member.immune = false
              if squad.isAlien
                member.moves = moveCapacities[if member.revealed then weapon else 'blip']
                member.weapons = alienCapacities.gretchin.weapons if member.twist is 'grenadierGretchin'
                member.twist = null
                # get alien moves from their kind if revealed, or 5 for blips
                unless member.revealed
                  # blip specific case: no attacks, just moves
                  member.rcNum = 0
                  member.ccNum = 0
              else
                # get marine moves from their weapon
                member.moves = moveCapacities[weapon]
                # suspensors act as bolters !
                member.moves = moveCapacities.bolter if member.equipment? and 'suspensors' in member.equipment
                # removes photon grenade on new turn
                if 'photonGrenade' in member.equipment
                  member.equipment.splice member.equipment.indexOf('photonGrenade'), 1
            
            # no alive squad members ? consider turn end
            squad.turnEnded = not hasAlive
            next()
        , (err) =>
          return callback err if err?
          game.turn++
          console.log "start of turn #{game.turn}"
          callback null
          
      # close doors that have been opened during moves
      if squad.isAlien
        return Item.where('map', squad.map.id).where('type', 'door').where('needClosure', true).exec (err, doors) =>
          return callback err if err?
          effects = [] 
          for door in doors
            effects.push makeState door, 'closed', 'imageNum'
            door.closed = true
            door.imageNum += 2
            door.needClosure = false
            @saved.push door
          if effects.length
            return addAction 'close', squad, effects, @, (err) =>
              return callback err if err?
              process()
          # no door to change
          process()
      # not an alien
      process()
  
module.exports = new EndOfTurnRule()