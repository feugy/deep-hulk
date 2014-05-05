Rule = require 'hyperion/model/Rule'

# Discard help if needed.
class DiscardHelpRule extends Rule

  # Applicables on player only
  # 
  # @param player [Item] the concerned player
  # @param target [Item] the concerned target
  # @param context [Object] extra information on resolution context
  # @param callback [Function] called when the rule is applied, with two arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback params [Array] array of awaited parameter (may be empty), or null/undefined if rule does not apply
  canExecute: (player, target, context, callback) =>
    callback null, if player?._className is 'Player' then [] else null

  # Modifies player's prefs regarding help displayal
  #
  # @param player [Item] the concerned player
  # @param target [Item] the concerned target
  # @param params [Object] associative array (may be empty) of awaited parametes, specified by resolve.
  # @param context [Object] extra information on execution context
  # @param callback [Function] called when the rule is applied, with one arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback result [Object] an arbitrary result of this rule.
  execute: (player, target, params, context, callback) =>
    player.prefs.discardHelp = true
    callback null
  
# A rule object must be exported. You can set its category (constructor optionnal parameter)
module.exports = new DiscardHelpRule 'help'