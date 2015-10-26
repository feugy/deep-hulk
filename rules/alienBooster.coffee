Rule = require 'hyperion/model/Rule'
ClientConf = require 'hyperion/model/ClientConf'
{useTwist, makeState} = require './common'

# "alienElite" and "amok" twist rule: for selected alien, double actions or close combats
class AlienBoosterRule extends Rule

  # Always appliable on alien squad if it has the relevant twist
  # 
  # @param game [Item] the concerned game
  # @param squad [Item] the concerned squad
  # @param context [Object] extra information on resolution context
  # @param callback [Function] called when the rule is applied, with two arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback params [Array] array of awaited parameter (may be empty), or null/undefined if rule does not apply
  canExecute: (game, squad, context, callback) =>
    # inhibit if waiting for deployment or other squad
    unless squad.isAlien and squad.waitTwist and squad.twist in ['alienElite', 'amok']
      return callback null, null 
      
    # select living revealed aliens/green skins on map 
    if squad.twist is 'amok' 
      filter = (member) -> member.kind in ['gretchin', 'ork']
    else
      filter = () -> true
    candidates = (member for member in squad.members when member.revealed and not member.dead and filter member)

    params = []
    if candidates.length > 0
      params.push
        name: 'target'
        type: 'object'
        within: candidates
    
    callback null, params

  # for alienElite, double moves, rcNum and ccNum. 
  # for amok, double rcNum.
  #
  # @param game [Item] the concerned game
  # @param squad [Item] the concerned alien squad
  # @param params [Object] associative array (may be empty) of awaited parametes, specified by resolve.
  # @param context [Object] extra information on execution context
  # @param callback [Function] called when the rule is applied, with one arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback result [Object] an arbitrary result of this rule.
  execute: (game, squad, params, context, callback) =>
    twist = squad.twist
    # no target found
    unless params.target?
      return useTwist twist, game, squad, [], @, callback

    # get labels
    ClientConf.findCached ['default'], (err, [conf]) =>
      return callback err if err?
      
      # get target alien
      for member in squad.members when member.id is params.target
        target = member
        break
      
      console.log "applied twist #{twist} on #{target.id} (#{target.kind})"
      
      effects = [makeState target, 'rcNum', 'ccNum', 'moves']
      
      # double relevant actions depending on twist
      if twist is 'alienElite'
        target.rcNum *= 2
        target.moves *= 2 
      target.ccNum *= 2
    
      useTwist twist, game, squad, effects, @, true, {alien: conf.values.labels[target.kind]}, callback
   
module.exports = new AlienBoosterRule 'twists'