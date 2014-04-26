Rule = require 'hyperion/model/Rule'
sanitizer = require 'sanitizer'
{warLogMax} = require './constants'

# Add a message in the game chat
class SendMessageRule extends Rule

  # Chat addition is allowed to current player within a given game (actor)
  # Execution is refused if player do not belong to the game, or if dead.
  # Expect "content" parameter (text).
  # 
  # @param actor [Item] the concerned game
  # @param squad [Item] the concerned squad
  # @param context [Object] extra information on resolution context
  # @param callback [Function] called when the rule is applied, with two arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback params [Array] array of awaited parameter (may be empty), or null/undefined if rule does not apply
  canExecute: (actor, squad, {player}, callback) =>
    return callback null, null unless actor?.type?.id is 'game' and squad?.player is player.email
    # check that player is in the game, and not dead
    for squad in actor.squads when squad.player is player.email and not squad.finished
      return callback null, [name: 'content', type: 'text']
    callback "You're not in this game !", null

  # Add the player name, a timestamp and the message content to the game chat.
  #
  # @param game [Item] the concerned game
  # @param squad [Item] the concerned squad
  # @param params [Object] associative array containing content parameter
  # @param context [Object] extra information on execution context
  # @param callback [Function] called when the rule is applied, with one arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback result [Object] an arbitrary result of this rule.
  execute: (game, squad, {content}, {player}, callback) =>
    # purge content to avoid injection
    content = sanitizer.sanitize content
    # add new entry at the begining.
    game.warLog.splice 0, 0, 
      kind: 'chat'
      squad: squad.name
      player: player.email
      time: new Date().getTime()
      content: content
    # removes old entries
    game.warLog = game.warLog[0..warLogMax] if game.warLog.length > warLogMax
    callback null
  
module.exports = new SendMessageRule 'chat'