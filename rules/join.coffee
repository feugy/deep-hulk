_ = require 'underscore'
Rule = require 'hyperion/model/Rule'
Item = require 'hyperion/model/Item'
{freeGamesId} = require './constants'
{resetHelpFlags} = require './common'

# Rule used to join an existing game
class JoinRule extends Rule

  # Rule apply if target is a game with remaining squad that does not have player
  # 
  # @param player [Player] the concerned player
  # @param game [Item] the concerned game
  # @param context [Object] extra information on resolution context
  # @param callback [Function] called when the rule is applied, with two arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback params [Array] array of awaited parameter, containing choosen squad 
  canExecute: (player, game, context, callback) =>
    return callback null, null unless game?.type?.id is 'game' and player?._className is 'Player'
    freeSquads = _.chain(game.squads).filter((squad) -> squad.player is null).pluck('name').value()
    if freeSquads.length > 0
      callback null, [
        name: 'squadName'
        type: 'string'
        within: freeSquads
      ]
    else
      callback null, null

  # Affect player to selected squad
  #
  # @param player [Player] the concerned player
  # @param game [Item] the concerned game
  # @param params [Object] associative array (may be empty) of awaited parametes, specified by resolve.
  # @param context [Object] extra information on execution context
  # @param callback [Function] called when the rule is applied, with one arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback result [Object] an arbitrary result of this rule.
  execute: (player, game, params, context, callback) =>
    console.log "player #{player.email} join game #{game.name} as squad #{params.squadName}"
    
    resetHelpFlags player
    
    # get free games list
    Item.findCached [freeGamesId], (err, [freeGames]) =>
      return callback err if err?
      return callback new Error "notFree #{freeGamesId}" unless freeGames?
      for squad in game.squads when squad.name is params.squadName
        # affect player to chosen squad
        squad.player = player.email
        player.characters.push squad
        
        # update game players array, but keep alien always at last position
        idx = game.players.length
        idx-- if not squad.isAlien and _.findWhere(game.players, squad:'alien')?
        game.players.splice idx, 0, player: player.email, squad: params.squadName
        
        # affect active squad wasn't set yet
        if game.singleActive and not game.squads[0].activeSquad?
          other.activeSquad = squad.name for other in game.squads
          
        # removes from free games if it was the last free squad
        unless _.find(game.squads, (squad) -> squad.player is null)?
          freeGames.games.splice freeGames.games.indexOf(game.id), 1
          console.log "game #{game.name} is full"
          # at last, update 
          @saved.push freeGames
          
      callback null
  
# A rule object must be exported. You can set its category (constructor optionnal parameter)
module.exports = new JoinRule 'init'