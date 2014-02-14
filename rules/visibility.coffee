_ = require 'underscore'
async = require 'async'
Item = require 'hyperion/model/Item'
Ratio = require './ratio'
{selectItemWithin, mergeChanges, distance} = require './common'
{wallPositions, doorPositions, alienCapacities, moveCapacities} = require './constants'

# Anything related to visibility:
# - tiles on line
# - is tile visible from another
# - blip revealing
# - wall positions
# - next wall/door on line
# - is tile reachable/targetable from character
module.exports = {

  # Returns walls position inside a given rectangle
  # Position are casted down into horizontal and vertical : 
  # horizontal[0][2] indicates a wall between the two first columns (y=0), at thrid row (x=2)
  # vertical[1][0] indicates a wall between rows 2 and 3 (x=1), at first column (y=0)
  #
  # @param from [Object] from position, one of the rectangle corner
  # @param to [Object] to position, the other corner
  # @param items [Array<Item>] all items that lies inside the rectangle. 
  # *Caution*: do not include items without position, or with position not inside the rectangle
  # @param withCharacters [Boolean] Takes in account living characters when checking visibility. Default to false
  # @return a details object with:
  # @option return low [Object] x and y coordinates of rectangle lower left corner
  # @option return verticals [Array<Array<Boolean>>] vertical walls matrix
  # @option return horizontals [Array<Array<Boolean>>] horizontal walls matrix
  getWalls: (from, to, items, withCharacters = false) ->
    walls =
      minX: Math.min from.x, to.x 
      minY: Math.min from.y, to.y
      maxX: Math.max from.x, to.x
      maxY: Math.max from.y, to.y
      vertical: [] 
      horizontal: []
      
    numH = Math.abs from.y-to.y
    numV = Math.abs from.x-to.x
    # compute walls within the selected rectangle
    for i in [0...numH]
      walls.horizontal.push (false for j in [0..numV])
    for j in [0...numV]
      walls.vertical.push (false for i in [0..numH])
      
    # search walls and occupant at start position
    for item in items 
      if walls.minX <= item?.x <= walls.maxX and walls.minY <= item?.y <= walls.maxY
        pos = {}
        if item.type.id is 'wall'
          # single wall
          pos = wallPositions[item.imageNum] 
        else if item.type.id is 'door'
          # closed door
          pos = doorPositions[item.imageNum] if item.closed
        else if withCharacters and item.type.id in ['alien', 'marine'] and not item.dead and not(item.x is from.x and item.y is from.y) and !(item.x is to.x and item.y is to.y)
          # characters occupy whole tile
          pos = top: true, bottom: true, left: true, right: true
        # complete wall matrix
        if pos.left and item.x-walls.minX isnt 0 
          walls.vertical[item.x-walls.minX-1][item.y-walls.minY] = true
        if pos.right and item.x-walls.minX isnt numV
          walls.vertical[item.x-walls.minX][item.y-walls.minY] = true
        if pos.bottom and item.y-walls.minY isnt 0
          walls.horizontal[item.y-walls.minY-1][item.x-walls.minX] = true
        if pos.top and item.y-walls.minY isnt numH
          walls.horizontal[item.y-walls.minY][item.x-walls.minX] = true
    walls
    
  # Compute tiles crossed by a straight from from to to.
  #
  # @param from [Object] from position
  # @param to [Object] to position
  # @return an array of coordinates between those two positions
  tilesOnLine: (from, to) ->
    #console.log "\n--- visibility from #{from.x}|#{from.y} to #{to.x}|#{to.y}"
    # get straight equation
    a = new Ratio from.y - to.y, from.x - to.x
    vertical = from.x - to.x is 0
    b = new Ratio(to.y, 1).subtract a.multiply to.x
    negate = a.valueOf() < 0
    invert = false
    tiles= []
    if vertical
      # vertical straight
      tiles = (x:from.x, y:y for y in [from.y..to.y])
    else if -1 <= a.valueOf() <= 1
      # flat straight: goes on x, and start with lowest
      if (to.x < from.x)
        [from, to] = [to, from] 
        invert = true
      tiles = [{x:from.x, y:from.y}]
      threshold = if a.equals 0 then new Ratio 0 else new Ratio(1).subtract a.abs()
      #console.log "> flat a:#{a}, b:#{b}, threshold:#{threshold}, negate:#{negate}"
      for x in [from.x...to.x]
        if a.equals 0
          y = b
        else
          y = a.multiply(x+0.5).add(b).add 1,2
        fY = Math.floor y.valueOf()
        diff = y.subtract fY
        diff = new Ratio(1).subtract diff if negate and !diff.equals 0
        #console.log "> flat x:#{x}, y:#{y}, fY:#{fY}, diff:#{diff}, sup:#{diff.subtract(threshold).numerator() > 0}"
        tiles.push x:x+1, y:(if negate and diff.equals 0 then fY-1 else fY)
        tiles.push x:x+1, y:(if negate then fY-1 else fY+1) if diff.subtract(threshold).numerator() > 0 and x+1 isnt to.x
    else
      # steep straight: goes on y, and start with lowest
      if (to.y < from.y)
        [from, to] = [to, from] 
        invert = true
      tiles = [{x:from.x, y:from.y}]
      threshold = if a.equals 0 then new Ratio 0 else new Ratio(1).subtract a.reciprocal().abs()
      #console.log "> steep a:#{a}, b:#{b}, threshold:#{threshold}, negate:#{negate}"
      for y in [from.y...to.y]
        x = new Ratio(y+0.5).subtract(b).divide(a).add 1,2
        fX = Math.floor x.valueOf()
        diff = x.subtract fX
        diff = new Ratio(1).subtract diff if negate and !diff.equals 0
        #console.log "> steep x:#{x}, y:#{y}, fX:#{fX}, diff:#{diff}, sup:#{diff.subtract(threshold).numerator() > 0}"
        tiles.push x:(if negate and diff.equals 0 then fX-1 else fX), y:y+1
        tiles.push x:(if negate then fX-1 else fX+1), y:y+1 if diff.subtract(threshold).numerator() > 0 and y+1 isnt to.y
          
    tiles.reverse() if invert
    #console.log JSON.stringify tiles, null, 0
    tiles
    
  # Indicates weither or not an actor can see a given target
  # 
  # @param from [Object] x/y coordinates of the concerned actor
  # @param to [Object] x/y coordinates of the checked target
  # @param items [Array<Item>] array of items inside the rectangle containing both from and to coordinates
  # @param withCharacters [Boolean] Takes in account characters when checking visibility. Default to false
  # @return null if target is visible, coordinate of obstacle otherwise
  hasObstacle: (from, to, items, withCharacters = false) ->
    # dead characters are not visible :)
    return to if to.dead
    return null if from?.x is to?.x and from?.y is to?.y
    #console.log "--- \n hasObstacle #{from.x}|#{from.y} -> #{to.x}|#{to.y}"
    # get tiles on the line, and walls
    tiles = module.exports.tilesOnLine from, to
    walls = module.exports.getWalls from, to, items, withCharacters
    #console.log ">> walls:", JSON.stringify walls, null, 2
    # now quit if one wall is crossed
    for i in [0..tiles.length-2]
      current = tiles[i]
      next = tiles[i+1]
      #console.log ">> check x:#{current.x} y:#{current.y} and x:#{next.x} y:#{next.y}"
      if next.x is current.x
        # on the same row: check horizontals
        [current, next] = [next, current] if next.y < current.y
        if walls.horizontal[current.y-walls.minY][current.x-walls.minX]
          #console.log "horizontal wall in horz"
          return next
      else if next.y is current.y
        # on the same column: check verticals
        [current, next] = [next, current] if next.x < current.x
        if walls.vertical[current.x-walls.minX][current.y-walls.minY]
          #console.log "vertical wall in vert"
          return current
      else 
        # neither on same column not row: check vertical on two tiles
        [current, next] = [next, current] if next.x < current.x
        vBottom = walls.vertical[current.x-walls.minX][current.y-walls.minY]
        vTop = walls.vertical[current.x-walls.minX][next.y-walls.minY]
        if vBottom and vTop
          #console.log "vertical wall"
          return current
           
        # check horizontal on two tiles (order tiles on y)
        [current, next] = [next, current] if next.y < current.y
        hLeft = walls.horizontal[current.y-walls.minY][current.x-walls.minX]  
        hRight = walls.horizontal[current.y-walls.minY][next.x-walls.minX]
        if hLeft and hRight
          #console.log "horizontal wall"
          return next 
          
        # check also wall angles: positive slope
        if ((hLeft and vBottom) or (hRight and vTop)) and current.x < next.x
          #console.log "horizontal angle"
          return next 
        
        # and negatice slope
        if ((hLeft and vTop) or (hRight and vBottom)) and current.x > next.x
          #console.log "vertical angle"
          return current 
        
    # no walls: it's visible
    null
    
  # Reveals all blips visible by a given marine, or check if the actor blip revealed himself
  #
  # @param actor [Item] concerned marine or blip
  # @param rule [Rule] caller rule, to save modified objects
  # @param effects [Array<Array>] for each modified model, an array with the modified object at first index
  # and an object containin modified attributes and their previous values at second index (must at least contain id).
  # @param callback [Function] end callback, invoked with 
  # @option callback error [Error] an error object, or null if no error occured
  detectBlips: (actor, rule, effects, callback) ->
    # select all items within map
    Item.where('map', actor.map.id).exec (err, items) =>
      return callback err if err?
      # merge items with saved/removed object
      mergeChanges items, rule
      
      reveal = (blip, end) =>
        # store previous blip state
        effects.push [blip, _.pick blip, 'id', 'moves', 'rcNum', 'ccNum', 'imageNum', 'revealed']
        blip.revealed = true
        blip.imageNum = alienCapacities[blip.kind].imageNum
        # subtract already done moves to possible moves
        blip.moves = moveCapacities[blip.weapon?.id or blip.weapon] - blip.moves
        blip.moves = 0 if blip.moves < 0
        blip.rcNum = 1
        blip.ccNum = 1
        # add attack action
        blip.fetch (err, blip) =>
          return end err if err?
          blip.squad.actions++
          console.log "reveal blip #{blip.kind} at #{blip.x}:#{blip.y}"
          # TODO : pas de detection automatique de la modification des actions de l'escouade !!!!
          # on est obligé de le déclarer nous même
          rule.saved.push blip, blip.squad
          end null
        
      # for a marine, check all other blips visibility
      if actor.type.id is 'marine'
        return async.each items, (blip, next) =>
          if blip.type.id is 'alien' and !blip.revealed and not module.exports.hasObstacle(actor, blip, items)?
            reveal blip, next
          else
            next()
        , (err) =>
          callback err
      else if actor.revealed is false
        # for an unrevealed blip, check if he revealed himself to other marines
        for marine in items when marine.type.id is 'marine' and not module.exports.hasObstacle(marine, actor, items)?
          return reveal actor , callback
      callback null
      
  # Indicates wether a field is reachable from a given character, to move on it
  # 
  # @param actor [Item] concerned character
  # @param field [Field] tested field
  # @param items [Array<Item>] all existing items on the map inthe actor/field rectangle
  # @return true if this field is reachable
  isReachable: (actor, field, items) ->
    # move possible if at distance 1, if field is marine own base and if field is visible
    return false unless field?.mapId is actor?.map?.id and 
        actor.moves >= 1 and 
        1 is distance(actor, field) and 
        (field.typeId[0..5] isnt 'base-' or field.typeId is "base-#{actor.squad.name}") and
        module.exports.hasObstacle(actor, field, items) is null
    # check target occupant
    occupant = _.find items, (item) -> item.x is field.x and 
      item.y is field.y and 
      item.type.id in ['marine', 'alien'] and
      not item.dead
    # can share tile with a squadmate, only if enought move to exit
    return !occupant? or (actor.squad.id is (occupant.squad.id or occupant.squad) and actor.moves >= 2)
  
  # Indicates wether a field/item target can be targeted with the given character weapon.
  # Common to range and close combat, thus you must check:
  # - weapon capabilities
  # - actor remaining attack
  # - target existence for close combat
  # Takes in account:
  # - target map and visibility
  # - flamer alignment specificity
  # Can be used asycnronously (without specifying items) or synchronously (by specifying items)
  #
  # @param actor [Item] concerned character
  # @param target [Field|Item] tested target field
  # @param itemsOrCallback [Array<Item>] items inside the rectangle defined by actor and target position. If a function, 
  # items are automatically retrieved, and the function invoked, with two arguments:
  # @option itemsOrCallback err [String] error string. Null if no error occured
  # @option itemsOrCallback reachable [Boolean] true if target is reachable
  # @returns Only if callback is an array, returns true is reachable, or false otherwise
  isTargetable: (actor, target, itemsOrCallback) ->
    if _.isArray itemsOrCallback
      callback = (err, result) ->
        throw new err if err?
        result
    else
      callback = itemsOrCallback
      
    return callback null, false unless target? and actor?
    # deny unless on same map and targeting a field (mapId)
    return callback null, false unless actor.map?.id and (actor.map.id is target.mapId or actor.map.id is target.map?.id)
    
    proceed = (err, items) ->
      return callback err, false if err?
      # abort unless target visible to actor (character blocks visibility unless using flamer)
      return callback null, false if module.exports.hasObstacle(actor, target, items, actor.weapon.id isnt 'flamer')?
      # depending on the weapon
      switch actor.weapon.id
        when 'flamer'
          # flamer allowed on horizontal, vertical or diagonal lines
          callback null, actor.x is target.x or actor.y is target.y or Math.abs(actor.x-target.x) is Math.abs actor.y-target.y
        when 'gloveSword', 'claws'
          # close combat only: check alignment and distance
          callback null, 1 is distance(actor, target) and (target.x is actor.x or target.y is actor.y)
        else
          callback null, true
          
    # synchronous behaviour
    if _.isArray itemsOrCallback
      return proceed null, itemsOrCallback
    # asynchronous bejaviour now check visibility rules: get all items at actor and target coordinates
    selectItemWithin actor.map.id, actor, target, proceed
                    
  # Search for the nearest wall on the line (horizontal, vertical or diagonal)
  #
  # @param mapId [String] id of current map
  # @param from [Object] shooter position (x/y coordinates)
  # @param to [Object] target position (x/y coordinates)
  # @param callback [Function] end callback, invoked with:
  # @option callback err [Error] an error object or null if no error occured
  # @option callback wall [Object] the nearest wall position (x/y coordinates)
  # @option callback items [Array<Item>] loaded items between shooter and wall
  untilWall: (mapId, from, to, callback) ->
    # get map dimensions
    Item.findCached ["game-#{mapId.replace 'map-', ''}"], (err, [game]) =>
      return callback err if err? or !game?
      [unused, lowX, lowY, upX, upY] = game.mapDimensions.match /^(.*):(.*) (.*):(.*)$/
      [lowX, lowY, upX, upY] = [+lowX, +lowY, +upX, +upY]
      target = 
        x: to.x
        y: to.y
      # are we horinzontal or vertical ?
      vertical = from.x is to.x
      horizontal = from.y is to.y
      # range will be the distance until the nearest map edge
      range = 100000
      unless horizontal
        # vertical line or diagonal
        target.y = if from.y < to.y then upY else lowY
        range = Math.min range, Math.abs to.y-target.y
      unless vertical
        # horizontal line or diagonal
        target.x = if from.x < to.x then upX else lowX
        range = Math.min range, Math.abs to.x-target.x
      # select all items within actor position and nearest map edge
      selectItemWithin mapId, from, target, (err, items) =>
        return callback err if err?
        prev = null
        current = null
        for i in [1..range]
          # invert if both actor and to are above 0
          i = -i if from.x <= 0 and to.x < 0
          prev = current if current?
          current = 
            x: to.x
            y: to.y
          # goes on next tile
          unless horizontal
            current.y += if from.y < to.y then i else -i
          unless vertical
            current.x += if from.x < to.x then i else -i
          # stop if next tile isnt visible
          if module.exports.hasObstacle(from, current, items)?
            return callback null, prev or to, items
        # no wall found: reach max range
        callback null, current, items
        
  # Find within next items a door to open, and returns it
  #
  # @param pos [Object] actor current position (with x and y coordinates)
  # @param items [Array<Model>] array of items within 1 range from actor
  # @return a door to open, or null.
  findNextDoor: (pos, items) ->
    openable = _.find items, (door) -> 
      match = false
      # returns closed door
      if door.type.id is 'door' and door.closed
        # but depending on the image, position must be check from both sides of the door
        switch door.imageNum
          # horizontal low doors
          when 2, 3 then match = pos.x is door.x and pos.y in [door.y-1, door.y]
          # horizontal up doors
          when 10, 11 then match = pos.x is door.x and pos.y in [door.y+1, door.y]
          # vertical doors
          when 6, 7, 14, 15 then match = pos.y is door.y and pos.x in [door.x-1, door.x]
      match
    return openable or null
}