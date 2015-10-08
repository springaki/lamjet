
path = require("path")

Promise     = require("promise")
coffee      = require("gulp-coffee")
gutil       = require("gulp-util")
jasmine     = require("gulp-jasmine")
install     = require("gulp-install")
zip         = require("gulp-zip")
runSequence = require("run-sequence")
del         = require("del")

FsWrapper     = require("./fs_wrapper")
LambdaWrapper = require("./lambda_wrapper")

module.exports = class Lamjet
  @setup: (gulp)->
    gulp.task "clean", (callback)->
      del(["./out", "./out.zip"], callback)

    gulp.task "compile", ->
      gulp.src("./src/**/*.coffee")
        .pipe(coffee()).on("error", gutil.log)
        .pipe(gulp.dest("./out"))

    gulp.task "copy-package-json", ->
      gulp.src("./package.json").
        pipe(gulp.dest("./out"))

    gulp.task "install-dependencies", ->
      gulp.src("./out/package.json")
        .pipe(install({production: true}))

    gulp.task "archive-to-zip", ->
      gulp.src(["out/**/*"])
        .pipe(zip("out.zip"))
        .pipe(gulp.dest("./"))

    gulp.task "build-zip", (callback)->
      return runSequence(
        ["clean"],
        ["compile"],
        ["copy-package-json"],
        ["install-dependencies"],
        ["archive-to-zip"],
        callback)

    gulp.task "deploy-to-aws-lambda", (callback)->
      config = require(path.join(process.cwd(), "aws-lambda-config.js"))
      lambda = new LambdaWrapper(region: config.region)

      console.log "Loading zip file..."
      FsWrapper.readFile("./out.zip")
        .then (result)->
          zipBody = result.body
          createFunctionParam = {
            FunctionName: config.functionName,
            Description:  config.description,
            Role:         config.role,
            MemorySize:   config.memorySize,
            Timeout:      config.timeout,
            Runtime:      config.runtime,
            Handler:      config.handler,
            Code:         {ZipFile: zipBody},
          }
          updateFunctionConfigurationParam = {
            FunctionName: config.functionName,
            Description:  config.description,
            Role:         config.role,
            MemorySize:   config.memorySize,
            Timeout:      config.timeout,
            Handler:      config.handler,
          }
          updateFunctionCodeParam = {
            FunctionName: config.functionName,
            ZipFile:      zipBody,
          }
          console.log "Creating function..."
          return lambda.createFunction(createFunctionParam)
            .then (result)->
              console.log "Created function."
              return Promise.resolve(result)
            .catch (result)->
              if result?.error?.statusCode == 409
                console.log "Function already exist"
                console.log "Updating function configuration..."
                return lambda.updateFunctionConfiguration(updateFunctionConfigurationParam)
                  .then (result)->
                    console.log "Update function code..."
                    return lambda.updateFunctionCode(updateFunctionCodeParam)
                  .then (result)->
                    console.log "Updated function."
                    return Promise.resolve(result)
              else
                return Promise.reject(result)
        .then (result)->
          console.log("Successful deploy function.")
          # callback()
        .catch (result)->
          console.log("Failed deploy function.")
          console.log(result)
          console.log(result.stack) if result?.stack?
          # callback(result)

    gulp.task "deploy", (callback)->
      return runSequence(
        ["build-zip"],
        ["deploy-to-aws-lambda"],
        callback)

    gulp.task "test", ->
      gulp.src("./out/**/*_spec.js")
        .pipe(jasmine({includeStackTrace: false}))

    gulp.task "auto-test", ->
      gulp.watch("./src/**/*.coffee", ["default"])
      gulp.start("default")

    gulp.task "default", ["compile"], ->
      gulp.start("test")
