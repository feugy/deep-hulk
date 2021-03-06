_ = require 'underscore'
Rule = require 'hyperion/model/Rule'
ClientConf = require 'hyperion/model/ClientConf'

updatePref = (player, pref, value) ->
  player.prefs.help = {} unless player.prefs.help
  player.prefs.help[pref] = value

displayTurn = (player, squad, values) ->
  # TODO
  if squad.actions < 4 
    if not player.prefs.help?.turnDisplayed
      updatePref player, 'turnDisplayed', true
      [msg: values.texts.help.endTurn, button: 'close']
    else if squad.isAlien and not player.prefs.help?.reinforceDisplayed
      updatePref player, 'reinforceDisplayed', true
      [msg: values.texts.help.reinforcement]
  else
    null
    
# Returns contextual help when player requires it
class HelpRule extends Rule

  # Help is avaiable for player that did not discarded message for their own squads.
  # Requires action parameter that indicate last player action.
  # 
  # @param player [Player] the concerned player
  # @param squad [Item] squad on which player needs help
  # @param context [Object] extra information on resolution context
  # @param callback [Function] called when the rule is applied, with two arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback params [Array] array of awaited parameter, or null/undefined if rule does not apply
  canExecute: (player, squad, context, callback) =>
    # unacceptable parameters
    unless player?._className is 'Player' and squad?.type?.id is 'squad'and _.findWhere(player.characters, id: squad.id)?
      return callback null, null
    # help discarded
    return callback null, null if player.prefs?.discardHelp
    return callback null, [
      {name: 'action', type:'string'}
    ]

  # Returns contextual help
  #
  # @param player [Player] the concerned player
  # @param squad [Item] squad on which player needs help
  # @param params [Object] associative array (may be empty) of awaited parametes, specified by resolve.
  # @param context [Object] extra information on execution context
  # @param callback [Function] called when the rule is applied, with one arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback result [Object] an arbitrary result of this rule.
  execute: (player, squad, {action}, context, callback) =>
    # get labels
    ClientConf.findCached ['default'], (err, [conf]) =>
      return callback err if err?
      result = null

      prefix = if squad.isAlien then 'alien' else 'marine'
      switch action
        when 'start'
          # at start, show welcome if nothing was done yet
          if squad.isAlien
            unless player.prefs.help?.scanDisplayed
              result = [msg: conf.values.texts.help["#{prefix}Welcome"], hPos: 'center', button: 'close']
          else
            unless player.prefs.help?.cursorDisplayed
              result = [
                {msg: conf.values.texts.help["#{prefix}Welcome"], hPos: 'center', button: 'next'}
                {msg: conf.values.texts.help.marinePanel, vPos: 'center'}
              ]
        when 'select'
          unless player.prefs.help?.cursorDisplayed
            result = [msg: conf.values.texts.help["#{prefix}Cursor"], vPos: 'bottom']
            if squad.activeSquad? and squad.activeSquad isnt squad.name
              result[0].msg += conf.values.texts.help.singleActive
              result[0].button = 'close'
            updatePref player, 'cursorDisplayed', true
        when 'startDeploy'
          unless player.prefs.help?.scanDisplayed
            result = [msg: conf.values.texts.help["#{prefix}Deploy"], vPos: 'bottom', hPos:'right', button: 'close']
            updatePref player, 'scanDisplayed', true
        when 'endDeploy'
          if not player.prefs.help?.panelDisplayed and squad.isAlien
            result = [msg: conf.values.texts.help.alienPanel, vPos: 'center']
            updatePref player, 'panelDisplayed', true
        when 'deploy'
          unless player.prefs.help?.deployedDisplayed
            result = [msg: conf.values.texts.help.deployed, vPos: 'bottom', hPos:'right', button: 'close']
            updatePref player, 'deployedDisplayed', true
        when 'move'
          unless player.prefs.help?.moveDisplayed
            result = [msg: conf.values.texts.help["#{prefix}Move"], vPos: 'bottom', button: if squad.isAlien then 'close' else undefined]
            updatePref player, 'moveDisplayed', true
          else 
            result = displayTurn player, squad, conf.values
        when 'order'
          unless player.prefs.help?.orderDisplayed
            result = [msg: conf.values.texts.help.marineOrder, vPos: 'bottom', hPos:'right', button: 'close']
            updatePref player, 'orderDisplayed', true
          
        when 'shoot', 'assault'
          unless player.prefs.help?.attackDisplayed
            result = [msg: conf.values.texts.help["#{prefix}Attack"], button: 'close']
            updatePref player, 'attackDisplayed', true
          else 
            result = displayTurn player, squad, conf.values
           
      if result is null and squad.points isnt 0 and not player.prefs.help?.missionDisplayed
        result = [msg: conf.values.texts.help["#{prefix}Mission"], button: 'close']
        updatePref player, 'missionDisplayed', true
            
      callback null, result
    
# A rule object must be exported. You can set its category (constructor optionnal parameter)
module.exports = new HelpRule 'help'