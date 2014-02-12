async = require 'async'
Rule = require 'hyperion/model/Rule'
{moveCapacities} = require './constants'

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
      # set to -1 to avoid same squad triggering multiple times end of turn
      squad.actions = -1
      for member in squad.members
        member.rcNum = 0
        member.ccNum = 0
        member.moves = 0
        
      console.log "end of turn #{game.turn} for squad #{squad.name}"
      # quit a first squad with remaining actions
      for other in game.squads when other isnt squad
        return callback null if other.actions >= 0
          
      # next turn ! Compute remaining actions for each squads
      async.each game.squads, (s, next) =>
        s.fetch (err, squad) =>
          # fetch squad to get members
          return next err if err?
          squad.actions = if squad.members.length > 0 then 0 else -1
          # reset each member, unless not on map
          for member in squad.members when member.map? and not member.dead
            squad.actions += 2
            # add an attack
            member.rcNum = 1
            member.ccNum = 1
            if squad.isAlien
              member.moves = moveCapacities[if member.revealed then member.weapon?.id or member.weapon else 'blip']
              # get alien moves from their kind if revealed, or 5 for blips
              unless member.revealed
                # blip specific case: no attacks, just moves
                squad.actions -= 1
                member.rcNum = 0
                member.ccNum = 0
            else
              # get marine moves from their weapon
              member.moves = moveCapacities[member.weapon?.id or member.weapon]
          next()
      , (err) =>
        return callback err if err?
        game.turn++
        console.log "start of turn #{game.turn}"
        callback null
  
module.exports = new EndOfTurnRule()