# credit to lmarkus/hubot-conversation for the original concept
_ = require 'underscore'
{inspect} = require 'util'
Dialogue = require './Dialogue'

# handles array of participants engaged in dialogue
# while engaged the robot will only follow the given dialogue choices
# entering a user scene will engage the user
# entering a room scene will engage the whole room
# entering a userRoom scene will engage the user in that room only
# @param robot, a hubot instance
# @param type (optional), participants - room, user (default) or userRoom
# @param opts (optional), key/vals for dialogue config, e.g overide reply method
class Scene
  constructor: (@robot, args...) ->

    # validate arguments / assume defaults
    if args[0]?
      if _.isString args[0] # type given
        @type = args[0]
        opts = args[1]? or {} # opts maybe given
      else if _.isObject args[0] # no type, but opts given
        opts = args[0]
    @type ?= 'user' # type fallback
    opts ?= {} # opts fallback

    if @type not in [ 'room', 'user', 'userRoom' ]
      throw new Error "invalid scene type given"

    # '@user hello' vs 'hello'
    replyDefault = if @type is 'room' then true else false

    # extend options with defaults (passed to dialogue)
    @config = _.defaults opts,
      reply: process.env.REPLY_DEFAULT or replyDefault

    # force type in case reply setting from environment var
    @config.reply = true if @config.reply? and @config.reply is 'true'
    @config.reply = false if @config.reply? and @config.reply is 'false'

    @engaged = {} # dialogues of each engaged participants
    @log = @robot.logger

    # hubot middleware re-routes to internal matching while engaged
    @robot.receiveMiddleware (c, n, d) => @middleware @, c, n, d

  # not called as method, but copied as a property
  middleware: (scene, context, next, done) =>
    res = context.response
    participants = @whoSpeaks res

    # check if incoming messages are part of active scene
    if participants of scene.engaged
      scene.log.debug "#{ participants } is engaged, routing dialogue."
      res.finish() # don't process regular listeners
      scene.engaged[participants].receive res # let dialogue handle the response
      done() # don't process further middleware.
    else
      scene.log.debug "#{ participants } not engaged, continue as normal."
      next done

  # return the source of a message (ID of user or room)
  whoSpeaks: (res) ->
    switch @type
      when 'room' then return res.message.room
      when 'user' then return res.message.user.id
      when 'userRoom' then return "#{res.message.user.id}_#{res.message.room}"

  # setup listener for scene entrance
  intro: (listenType, regex) ->

  # engage the participants in dialogue
  # @param res, the response object
  # @param opts (optional), key/vals for dialogue config, e.g overide timeout
  enter: (res, opts={}) ->

    # extend dialogue options with scene config
    opts = _.defaults @config, opts

    # setup dialogue to handle choices for response branching
    participants = @whoSpeaks res
    return null if @inDialogue participants
    @log.info "Engaging #{ @type } #{ participants } in dialogue"
    @engaged[participants] = new Dialogue res, opts

    # remove participants from engaged participants on timeout or completion
    @engaged[participants].on 'timeout', => @exit res, 'timeout'
    @engaged[participants].on 'end', (completed) =>
      @exit res, "#{ if completed then 'complete' else 'incomplete' }"
    return @engaged[participants] # return started dialogue

  # disengage an participants from dialogue (can help in case of error)
  exit: (res, reason='unknown') ->
    participants = @whoSpeaks res
    if @engaged[participants]?
      @log.info "Disengaging #{ @type } #{ participants } because #{ reason }"
      @engaged[participants].clearTimeout()
      delete @engaged[participants]
      return true

    # user may have been already removed by timeout event before end:incomplete
    @log.debug "Cannot disengage #{ participants }, not in #{ @type } scene"
    return false

  # end all engaged dialogues
  exitAll: ->
    @log.info "Disengaging all in #{ @type } scene"
    _.invoke @engaged, 'clearTimeout'
    @engaged = []

  # return the dialogue for an engaged participants
  dialogue: (participants) -> return @engaged[participants] or null

  # return the engaged status for an participants
  inDialogue: (participants) -> return participants in _.keys @engaged

module.exports = Scene
