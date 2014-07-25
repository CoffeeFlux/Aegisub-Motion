ffi = require "ffi"
log = require "a-mo.Log"

class TrimHandler

	windows: ffi.os == "Windows"

	-- Set up encoder presets.
	defaults: {
		x264:    '"#{encbin}" --crf 16 --tune fastdecode -i 250 --fps 23.976 --sar 1:1 --index "#{prefix}#{index}.index" --seek #{startf} --frames #{lenf} -o "#{prefix}#{output}[#{startf}-#{endf}].mp4" "#{inpath}#{input}"'
		--"#{encbin}" -ss #{startt} -i "#{inpath}#{input}" -vframes #{lenf} "#{prefix}#{output}[#{startf}-#{endf}]-%%05d.jpg"
		ffmpeg:  '"#{encbin}" -ss #{startt} -t #{lent} -sn -i "#{inpath}#{input}" "#{prefix}#{output}[#{startf}-#{endf}]-%%05d.jpg"'
		avs2yuv: 'echo FFVideoSource("#{inpath}#{input}",cachefile="#{prefix}#{index}.index").trim(#{startf},#{endf}).ConvertToRGB.ImageWriter("#{prefix}#{output}-[#{startf}-#{endf}]\\",type="png").ConvertToYV12 > "#{prefix}encode.avs"\nmkdir "#{prefix}#{output}-[#{startf}-#{endf}]"\n"#{encbin}" -o NUL "#{prefix}encode.avs"\ndel "#{prefix}encode.avs"'
	}

	-- trimConfig is just the trim subtable of the config table collection.
	new: ( trimConfig ) =>
		@tokens = { }
		@encodeCommand = trimConfig.enccom
		with @tokens
			.encbin = trimConfig.encbin
			.prefix = trimConfig.prefix
			.inpath = aegisub.decode_path "?video/"
		getVideoName!

	getVideoName = =>
		with @tokens
			video = aegisub.project_properties!.video_file
			assert video\len! != 0, "Theoretically it should be impossible to get this error."
			tokens.input = video\sub .inpath\len! + 1

	calculateTrimLength: ( lineCollection ) =>
		with @tokens
			.startt = lineCollection.startTime
			.endt   = lineCollection.endTime
			.lent   = .endt - .startt
			.startf = lineCollection.startFrame
			.endf   = lineCollection.endFrame
			.lenf   = lineCollection.totalFrames

	performTrim: =>
		with platform = ({
				[true]:  {
					pre: os.getenv('TEMP')
					ext: ".bat"
					exec: '""%s""'
					postExec: "\nif errorlevel 1 (echo Error & pause)"
					execFunc: ( encodeScript ) ->
						os.execute encodeScript
				}
				[false]: {
					pre: "/tmp"
					ext: ".sh"
					exec: 'sh "%s"'
					postExec: " 2>&1"
					execFunc: ( encodeScript ) ->
						output = io.popen encodeScript
						log.debug output\read '*a'
						output\close!
				}
			})[@windows]

			encodeScript = aegisub.decode_path "#{.pre}/a-mo.encode#{.ext}"
			encodeScriptFile = io.open encodeScript, "w+"
			unless encodeScriptFile
				log.windowError "Encoding script could not be written.\nSomething is wrong with your temp dir (#{.pre})."
			encodeScriptFile\write @encodeCommand\gsub( "#(%b{})", ( token ) -> @tokens[token\sub 2, -2] ) .. .postExec
			encodeScriptFile\close!
			.execFunc .exec\format encodeScript
