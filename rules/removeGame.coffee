Rule = require 'hyperion/model/Rule'
Map = require 'hyperion/model/Map'

# remove a game, and all maps, event and team associate.
# only for administrators
class RemoveGameRule extends Rule

  # Apply on games when connected player is administrator
  # 
  # @param actor [Item] the concerned actor
  # @param target [Item] the concerned target
  # @param context [Object] extra information on resolution context
  # @param callback [Function] called when the rule is applied, with two arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback params [Array] array of awaited parameter (may be empty), or null/undefined if rule does not apply
  canExecute: (actor, game, context, callback) =>
    callback null, if game?.type?.id is 'game' and context.player?.isAdmin then [] else null

  # Remove the game, all the corresponding events, and the map.
  # Removing the map will also destroy wall, doors and characters on it.
  #
  # @param actor [Item] the concerned actor
  # @param target [Item] the concerned target
  # @param params [Object] associative array (may be empty) of awaited parametes, specified by resolve.
  # @param context [Object] extra information on execution context
  # @param callback [Function] called when the rule is applied, with one arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback result [Object] an arbitrary result of this rule.
  execute: (actor, game, params, context, callback) =>
    # removes team members cause they may not be on map
    for squad in game.squads
      @removed.push squad
      @removed.push member for member in squad.members
    # removes actions
    @removed.push action for action in game.nextActions
    @removed.push action for action in game.prevActions
    # then map
    mapId = game.id.replace 'game', 'map'
    Map.findCached [mapId], (err, [map]) =>
      err = "no map with id #{mapId}" unless err? or map?
      return callback "failed to retrieve map #{mapId}: #{err}" if err?
      @removed.push map
      # then game itself
      @removed.push game
      callback null
  
module.exports = new RemoveGameRule 'administration'