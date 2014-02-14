_ = require 'underscore'
Rule = require 'hyperion/model/Rule'
removeGame = require './removeGame'
{mergeChanges} = require './common'

# When player acknoledge a game's end
class EndOfGameRule extends Rule

  # May apply only for player on one of it's finished game
  # 
  # @param player [Player] the concerned player
  # @param game [Item] the concerned game
  # @param context [Object] extra information on resolution context
  # @param callback [Function] called when the rule is applied, with two arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback params [Array] array of awaited parameter (may be empty), or null/undefined if rule does not apply
  canExecute: (player, game, context, callback) =>
    callback null, if game?.finished and _.find(player.characters, (squad) -> squad.game is game?.id)? then [] else null

  # removes the squad from player's characters, and destroy game and map if no other squad remains
  #
  # @param player [Player] the concerned player
  # @param game [Item] the concerned game
  # @param params [Object] associative array (may be empty) of awaited parametes, specified by resolve.
  # @param context [Object] extra information on execution context
  # @param callback [Function] called when the rule is applied, with one arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback result [Object] an arbitrary result of this rule.
  execute: (player, game, params, context, callback) =>
    console.log "player #{player.email} confirm finished game #{game.name}"
    # remove concerned squad from player's characters to avoid playing again
    squad = _.find player.characters, (squad) -> squad.game is game?.id
    player.characters.splice player.characters.indexOf(squad), 1
    # mark squad as finished
    squad.finished = true
    @saved.push squad
    
    # when all players have finished, remove game
    if _.every(game.squads, (squad) -> squad.finished)
      removeGame.execute player, game, params, {player: isAdmin:true}, (err) =>
        console.log "remove game #{game.name} and map #{squad.map}", err
        console.error err if err?
        @saved = @saved.concat removeGame.saved
        @removed = @saved.concat removeGame.removed
        callback err
    else
      callback null  
    
module.exports = new EndOfGameRule()