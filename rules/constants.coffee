  
heavyWeapons = ["flamer", "autoCannon", "missileLauncher"]
commanderWeapons = ["heavyBolter", "gloveSword", "pistolAxe"]
marineWeapons = ["bolter"].concat heavyWeapons

# Common constants
module.exports = {
  
  # Maximum of games a player can create
  maxGames: 5
  
  # Maximum entries in the war log
  warLogMax: 100
  
  # id of list game object that contains free games
  freeGamesId: 'freeGames'
  
  # images rank corresponding to squad ids
  squadImages: 
    alien: 0
    ultramarine: 1
    imperialfist: 2
    bloodangel: 3

  # heavy weapon ids for simple marines 
  heavyWeapons: heavyWeapons
  
  # weapon ids for commanders
  commanderWeapons: commanderWeapons
  
  # weapon ids for simple marines
  marineWeapons: marineWeapons

  # all possible marines and commanders weapon
  weapons: commanderWeapons.concat marineWeapons
  
  # walls position from their image index
  wallPositions: [
    {top: true}
    {right: true}
    {bottom: true}
    {left: true}
    {top: true, right: true}
    {top: true, left: true}
    {bottom: true, right: true}
    {bottom: true, left: true}
  ]
      
  # door position from their image index
  # **CAUTION** don't forget to update position when door ItemType images are modified !
  doorPositions: [
    {bottom: false}
    {bottom: false}
    {bottom: true}
    {bottom: true}
    {left: false}
    {left: false}
    {left: true}
    {left: true}
    {top: false}
    {top: false}
    {top: true}
    {top: true}
    {left: false}
    {left: false}
    {left: true}
    {left: true}
    {right: false}
    {right: false}
    {right: true}
    {right: true}
  ]
  
  # image indexes for a given weapon
  weaponImages: 
    ultramarine: {heavyBolter: 1, gloveSword: 2, pistolAxe: 0, bolter: 3, autoCannon: 4, flamer: 5, missileLauncher:6}
    imperialfist: {heavyBolter: 8, gloveSword: 9, pistolAxe: 7, bolter: 10, autoCannon: 11, flamer: 12, missileLauncher:13}
    bloodangel: {heavyBolter: 15, gloveSword: 16, pistolAxe: 14, bolter: 17, autoCannon: 18, flamer: 19, missileLauncher:20}

  # move capacities, depending on the equiped weapon
  moveCapacities:
    assaultRifle: 4
    autoCannon: 4
    blip: 5
    bolter: 6
    claws: 8
    dreadnoughtBolter: 4
    flamer: 4
    gloveSword: 6
    heavyBolter: 6
    missileLauncher: 4
    pistolAxe: 6
    slugga: 8
    shoota: 6
    trap: 0
    
  # store moves, armor and weapon capacities for aliens
  # use the same names as alien properties to allow quick copy during creation
  alienCapacities:
    ork:
      armor: 1
      weapons: ['shoota']
      points: 3
      imageNum: 1
    gretchin:
      armor: 0
      weapons: ['slugga']
      points: 2
      imageNum: 2
    android:
      armor: 2
      weapons: ['assaultRifle']
      points: 10
      imageNum: 3
    chaosCommander:
      armor: 2
      weapons: ['heavyBolter']
      points: 10
      imageNum: 4
    chaosMarine:
      armor: 2
      weapons: ['bolter']
      points: 5
      imageNum: 5
    chaosHeavyMarine:
      armor: 2
      weapons: ['missileLauncher']
      points: 10
      imageNum: 6
    dreadnought:
      armor: 4
      life: 3
      noHCenter: true
      weapons: ['dreadnoughtBolter']
      points: 25
      imageNum: 
        missileLauncher_autoCannon: 7
        missileLauncher_flamer: 8
        autoCannon_missileLauncher: 7
        autoCannon_flamer: 9
        flamer_autoCannon: 9
        flamer_missileLauncher: 8
    genestealer:
      armor: 3
      weapons: ['claws']
    trap:
      dead: true
      weapons: ['smallLaser', 'missileLauncher']
      x: 0
      y: 0
      
  # possible equipment for marine squad
  equipments:
    ultramarine: ['digitalWeapons', 'mediKit', 'detector', 'targeter', 'targeter', 'pistolBolters', 'meltaBomb', 'blindingGrenade']
    imperialfist: ['bionicEye', 'combinedWeapon', 'suspensors', 'targeter', 'targeter', 'pistolBolters', 'meltaBomb', 'blindingGrenade']
    bloodangel: ['bionicArm', 'forceField', 'assaultBlades', 'targeter', 'targeter', 'pistolBolters', 'meltaBomb', 'blindingGrenade']
  
  # possible orders for marine squad
  orders:
    ultramarine: ['fireAtWill', 'goGoGo', 'toDeath', 'bySections']
    imperialfist: ['fireAtWill', 'goGoGo', 'bySections', 'heavyWeapon']
    bloodangel: ['fireAtWill', 'goGoGo', 'toDeath', 'photonGrenade']
    
  # List of possible twists
  twists: [
    'generalControl'
    'redeployment'
    'alienTeleporter'
    'grenadierGretchin'
    'mekaniakOrk'
    'suicideAndroid'
    'amok'
    'alienElite'
    'bewitchment'
    'jammedWeapon'
    'depletedMunitions'
    'mine'
    'defectiveEquipment'
    'defectiveCommunications'
    'operationsReport'
    'trappedCorridor'
    'trappedCorridor'
    'newOrder'
    'combatPlan'
    'mothershipCaptain'
    'alienSpecialForces'
    'generalAssault'
    'mothershipDetector'
    'defectiveAndroids'
    'psychoAttack'
  ]
}