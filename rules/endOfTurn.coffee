_ = require 'underscore'
async = require 'async'
Rule = require 'hyperion/model/Rule'
Item = require 'hyperion/model/Item'
{moveCapacities} = require './constants'
{hasSharedPosition, addAction} = require './common'

# When player has finished its turn, may trigger another turn
class EndOfTurnRule extends Rule

  # May apply only if remaining or 0 actions at squad level.
  # 
  # @param player [Player] the concerned player
  # @param squad [Item] the concerned squad
  # @param context [Object] extra information on resolution context
  # @param callback [Function] called when the rule is applied, with two arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback params [Array] array of awaited parameter (may be empty), or null/undefined if rule does not apply
  canExecute: (player, squad, context, callback) =>
    # inhibit if waiting for deployment
    return callback null, null if squad?.deployZone?
    return callback null, if squad?.type?.id is 'squad' and squad?.actions >= 0 then [] else null

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
      squad.actions = -1
      console.log "end of turn #{game.turn} for squad #{squad.name}"
      
      # in single player mode, set next player as active
      if game.singleActive
        active = 'none'
        for obj, i in game.players when obj.squad is squad.name
          if game.players[i+1]?
            active = game.players[i+1].squad
            break
        other.activeSquad = active for other in game.squads
        
      process = =>
        # quit a first squad with remaining actions
        for other in game.squads when other.id isnt squad.id
          return callback null if other.actions >= 0
           
        # next turn ! in singl player mode, set first player as active
        if game.singleActive
          other.activeSquad = game.players[0].squad for other in game.squads
          
        # compute remaining actions for each squads
        async.each game.squads, (s, next) =>
          s.fetch (err, squad) =>
            # fetch squad to get members
            return next err if err?
            squad.actions = 0
            squad.firstAction = true
            # reset number of blip to reveal
            squad.revealBlips = 3 if 'detector' in squad.equipment
            # reset number of blip to reinforce
            squad.supportBlips = 6 if squad.isAlien
            
            # reset each member, unless not on map
            for member in squad.members when member.map? and not member.dead
              # use first weapon to get allowed moves
              weapon = member.weapons[0]?.id or member.weapons[0]
              squad.actions += 2
              # add an attack
              member.rcNum = 1
              member.ccNum = 1
              member.usedWeapons = []
              # remove blinding grenade immunity
              member.immune = false
              if squad.isAlien
                member.moves = moveCapacities[if member.revealed then weapon else 'blip']
                # get alien moves from their kind if revealed, or 5 for blips
                unless member.revealed
                  # blip specific case: no attacks, just moves
                  squad.actions -= 1
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
                  
            # no alive squad members ? set to -1 to prevent player hitting next turn
            squad.actions = 0 if squad.actions is -1
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
            effects.push [door, _.pick door, 'closed', 'imageNum']
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