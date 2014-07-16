util = require "util"

class Line
	fieldsToCopy: {
		"actor"
		"class"
		"comment"
		"effect"
		"end_time"
		"extra"
		"layer"
		"margin_l"
		"margin_r"
		"margin_t"
		"section"
		"start_time"
		"style"
		"text"
	}

	new: ( line, @parentCollection ) =>
		for field in ipairs fieldsToCopy
			@[field] = line[field]
		@duration = @end_time - @start_time

		-- This function is way longer than it should be, but it performs all
	-- of the necessary operations to get the lines ready for tracking,
	-- which, as it turns out, is quite a lot.
	mungeForFBF: ( ) =>
		shortFade = "\\fad%(([%d]+),([%d]+)%)"
		longFade  = "\\fade%(([%d]+),([%d]+),([%d]+),([%-%d]+),([%-%d]+),([%-%d]+),([%-%d]+)%)"
		alpha_from_style = util.alpha_from_style
		combineChar = string.char 6
		pow = math.pow

		appendMissingTags = ( block, styleRef ) ->
			for tag, str in pairs @importantTags
				if opts[str.opt] and not block\match tag .. "[%-%d%.]+"
					styleDefault = styleRef[str.key]
					if tonumber( styleDefault ) != str.skip
						block ..= (tag.."%.2f")\format styleDefault
			block

		lexTransforms = ( transform, line ) ->
			transStart, transEnd, transExp, transEffect = transform\match "%(([%-%d]*),?([%-%d]*),?([%d%.]*),?(.+)%)"
			transExp = tonumber( transExp ) or 1
			transStart = tonumber( transStart ) or 0

			transEnd = tonumber( transEnd ) or 0
			if transEnd == 0
				transEnd = line.duration

			table.insert line.transformations, { transStart, transEnd, transExp, transEffect }
			debug "Line %d: \\t(%g,%g,%g,%s) found", transStart, transEnd, transExp, transEffect

		fadToTransform = ( fadStart, fadEnd, alpha, duration ) ->
			local str
			if fadStart > 0
				str = ("\\alpha&HFF&\\t(%d,%s,1,\\alpha%s)")\format 0, fadStart, alpha
			if fadEnd > 0
				str ..= ("\\t(%d,%d,1,\\alpha&HFF&)")\format duration - fadEnd, duration
			str

		-- The first fad or fade that is found in the line is the one
		-- that is used.
		shortFadeStartPos, shortFadeEndPos = @text\find shortFade
		longFadeStartPos, longFadeEndPos   = @text\find longFade

		-- Make the position a property of the line table, since they'll be
		-- used later to calculate the offset.
		-- I refuse to support \a.
		alignment = @text\match("\\an([1-9])") or @styleref.align
		@xPosition, @yPosition = @text\match "\\pos%(([%-%d%.]+),([%-%d%.]+)%)"
		@xOrigin,   @yOrigin   = @text\match "\\org%(([%-%d%.]+),([%-%d%.]+)%)"
		verticalMargin = if @margin_v == 0 then @styleref.margin_v else @margin_v
		leftMargin     = if @margin_l == 0 then @styleref.margin_l else @margin_l
		rightMargin    = if @margin_r == 0 then @styleref.margin_r else @margin_r


		-- If both \fad and \fade are present, then get rid of all
		-- occurrences of whichever one does not come first.
		if shortFadeStartPos and longFadeStartPos
			if shortFadeStartPos < longFadeStartPos
				@text = @text\gsub longFade, ""
				longFadeStartPos = nil
			else
				@text = @text\gsub shortFade, ""
				shortFadeStartPos = nil

		-- For both \fad and \fade, make sure that there are not repeat
		-- occurrences of the tag and move them to the beginning of the
		-- line. This should theoretically ensure identical behavior
		-- when they are turned into \t.
		local fadStartTime, fadEndTime
		if shortFadeStartPos
			fadStartTime, fadEndTime = @text\sub( shortFadeStartPos+5, shortFadeEndPos-1 )\match( "(\d+),(\d+)" )
			fadStartTime, fadEndTime = tonumber( fadStartTime ), tonumber( fadEndTime )
			@text = "{#{@text\sub shortFadeStartPos, shortFadeEndPos}}#{@text\gsub shortFade, ""}"
		if longFadeStartPos
			@text = "{#{@text\sub longFadeStartPos, longFadeEndPos}}#{@text\gsub longFade, ""}"

		-- Merge all contiguous comment/override blocks. This will make
		-- pretty much everything that follows a lot more sane.
		@text = @text\gsub "}{", combineChar

		-- Perform operations on the first override block of the line.
		@text = @text\gsub "^{(.-)}", ( tagBlock ) ->

			if @parentCollection.config.xPosition or @parentCollection.config.yPosition and not @xPosition
				@xPosition = @xPosition[alignment%3+1] @parentCollection.meta.res_x, leftMargin, rightMargin
				@yPosition = @yPosition[math.ceil alignment/3] @parentCollection.meta.res_y, verticalMargin
				tagBlock = ("\\pos(%.3g,%.3g)")\format( @xPosition, @yPosition ) .. tagBlock

			if @parentCollection.config.origin and not @xOrigin
				@xOrigin = @xPosition
				@yOrigin = @yPosition
				tagBlock = ("\\org(%.3g,%.3g)")\format( @xOrigin, @yOrigin ) .. tagBlock

			if shortFadeStartPos
				replaced = false
				-- Not pedantically correct, as output will not be properly
				-- preserved with lines that set specific alpha values, such
				-- as \1a and so on. Additionally, doesn't handle the case
				-- of multiple alpha tags being placed in the same override
				-- block, and so can spawn more transforms than necessary.
				tagBlock = tagBlock\gsub "\\alpha(&H%x%x&)", ( alpha ) ->
					replaced = true
					fadToTransform fadStartTime, fadEndTime, alpha, @duration
				unless replaced
					-- Has the same problem mentioned above.
					tagBlock ..= fadToTransform fadStartTime, fadEndTime, alpha_from_style( @styleref.color1 ), @duration
			elseif longFadeStartPos
				-- This is also completely wrong, as existing alpha tags
				-- aren't even taken into account. However, in this case,
				-- properly handling the fade is much more complex, as alpha
				-- tags influence both the starting and ending transparency
				-- of the fade in an additive fashion. Given that very few
				-- (if any) people use \fade, I don't think the effort
				-- necessary to fix this behavior is worth it at the moment.
				tagBlock = tagBlock\gsub "\\fade%(([%d]+),([%d]+),([%d]+),([%-%d]+),([%-%d]+),([%-%d]+),([%-%d]+)%)",
					(a, b, c, d, e, f, g) ->
						("\\alpha&H%02X&\\t(%s,%s,1,\\alpha&H%02X&)\\t(%s,%s,1,\\alpha&H%02X&)")\format(a, d, e, b, f, g, c)

			tagBlock\gsub "\\t(%b())", ( tContents ) ->
				lexTransforms tContents, line

			-- There is no check for \r in the first tag block in this
			-- code, so in theory, it will do the wrong thing in certain
			-- scenarios. However, if you are putting \r[style] at the
			-- beginning of your line you are an idiot.
			tagBlock = appendMissingTags tagBlock, @styleref

			-- Purposefully leave the opening tag off so that the first block
			-- will not get picked up in the following block manipulations.
			-- This will cause problems if someone is an idiot and has {
			-- embedded in their first override block, but there is no valid
			-- reason for that. (Actually there is, but it's an extremely bad
			-- one and belongs to a case I have already disowned).
			tagBlock .. '}'

		@text = @text\gsub "{(.-)}", ( tagBlock ) ->
			if shortFadeStartPos
				tagBlock = tagBlock\gsub "\\alpha(&H%x%x&)", ( alpha ) ->
					fadToTransform fadStartTime, fadEndTime, alpha, @duration

			tagBlock\gsub "\\t(%b())", ( tContents ) ->
				lexTransforms tContents, line

			-- The scope abuse inside of this gsub is pretty awkward.
			tagBlock\gsub "\\r([^\\}#{combineChar}]*)", ( resetStyle ) ->
				styleRef = @parentCollection.styles[rstyle] or @styleref
				tagBlock = appendMissingTags( tagBlock, styleRef )

		-- It is possible to have both a rectangular and vector clip in
		-- the same line. This is useful for masking lines with
		-- gradients. In order to be able to support this (even though
		-- motion tracking gradients is a bad idea and not endorsed by
		-- this author), we need to both support multiple clips in one
		-- line, as well as not convert rectangular-style clips to
		-- vector clips. To make our lives easier, we'll just not
		-- enforce any limits on the number of clips in a line and
		-- assume the user knows what they're doing.
		@text = @text\gsub "\\(i?clip)(%b())", ( clip, points ) ->
			@hasClip = true
			if points\match "[%-%d%.]+, *[%-%d%.]+, *[%-%d%.]+"
				@hasRectangularClip = true
			else
				@hasVectorClip = true
				points = points\gsub "%(([%d]*),?(.-)%)", ( scaleFactor, points ) ->
					if scaleFactor ~= ""
						scaleFactor = tonumber scaleFactor
						-- Other number separators such as ',' are valid in
						-- vector clips, but standard tools don't create them.
						-- Ignore that parser flexibility to make our lives less
						-- difficult. Convert everything to floating point
						-- values for simplicity's sake.
						points = points\gsub "([%.%d%-]+) ([%.%d%-]+)", ( x, y ) ->
							x = tonumber( x )/2^(scaleFactor - 1)
							y = tonumber( y )/2^(scaleFactor - 1)
							-- Round the calculated values so that they don't take
							-- up huge amounts of space.
							("%.3g %.3g")\format x, y
					points
			"\\#{clip}(#{points})"

	cleanText: =>
		cleantrans = ( transform ) ->
			transStart, transEnd, transExp, transEffect = cont\sub(2,-2)\match "([%-%d]+),([%-%d]+),([%d%.]*),?(.+)"
			-- This specific section only works on transforms we have
			-- generated. Otherwise, an end time of 0 will mean the transform
			-- runs to the end of the line.
			if tonumber( transEnd ) <= 0
				return ("%s")\format transEffect
			elseif tonumber( transStart ) > @duration or tonumber( transEnd ) < tonumber( transStart )
				return ""
			elseif tonumber( transExp ) == 1 or transExp == ""
				return ("\\t(%s,%s,%s)")\format transStart, transEnd, transEffect
			else
				return ("\\t(%s,%s,%s,%s)")\format transStart, transEnd, transExp, transEffect

		-- merge sequential override blocks if they are marked as being the ones we wrote
		@text = @text\gsub "}"..string.char(6).."{", ""
		-- remove superfluous marker characters for when there is no override block at the beginning of the original line
		@text = @text\gsub string.char(6), ""
		-- clean up transformations (remove transformations that have completed)
		@text = @text\gsub "\\t(%b())", cleantrans
		-- I think this is irrelevant. But whatever.
		@text = @text\gsub "{}", ""

		for overrideBlock in @text\gmatch "{(.-)}"
			transforms = {}
			@text = @text\gsub "\\(i?clip)%(1,m", "\\%1(m"

			overrideBlock = overrideBlock\gsub "(\\t%b())", (transform) ->
				debug "Cleanup: %s found", transform
				table.insert transforms, transform
				string.char(3)

			for k, v in pairs alltags
				_, num = overrideBlock\gsub(v, "")
				overrideBlock = overrideBlock\gsub v, "", num - 1

			for trans in *transforms
				overrideBlock = overrideBlock\gsub string.char(3), trans, 1

			@text = @text\gsub "{.-}", string.char(1)..overrideBlock..string.char(2), 1

		@text = @text\gsub string.char(1), "{"
		@text = @text\gsub string.char(2), "}"
		.effect = .effect\gsub "aa%-mou", "", 1