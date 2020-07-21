require 'find'
require 'json'
require 'open3'
require 'yaml'

def get_env_variable(key)
	return (ENV[key] == nil || ENV[key] == "") ? nil : ENV[key]
end

platform_type = get_env_variable("AC_PLATFORM_TYPE") || abort('Missing AC_PLATFORM_TYPE variable.')
repo_path = get_env_variable("AC_REPOSITORY_DIR") || abort('Missing repository path.')
env_var_path = get_env_variable("AC_ENV_FILE_PATH") || abort('Missing environment variable path.')
temporary_path = get_env_variable("AC_TEMP_DIR") || abort('Missing temporary path.')

build_gradle_files=["build.gradle", "build.gradle.kts"]
settings_gradle_files=["settings.gradle", "settings.gradle.kts"]

def get_build_gradle_path(module_path, build_files)
    build_files.each do |elem|
        absPath="#{module_path}/#{elem}"
        if File.exist?(absPath)
            return absPath
        end
    end
    return nil
end

def is_application_module(module_path,build_gradle_files)
    build_file_path= get_build_gradle_path(module_path, build_gradle_files)
    if !build_file_path.nil?
        File.open(build_file_path, "r") do |f|
            f.each_line do |line|
                if line.include?("com.android.application")
                   return true
                end
            end
          end
    end
    return false
end

def get_settings_gradle_path(dRepo_path, settings_files)
    settings_files.each do |elem|
        absPath="#{dRepo_path}/#{elem}"
        if File.exist?(absPath)
            return absPath
        end
    end
    return nil
end

def find_projects_root_path(repo_path, settings_files)
    projects = []
    Find.find("#{repo_path}") do |path| 
        if settings_files.include? File.basename(path)
            projects.push(File.dirname(path))
        end
    end
    return projects
end

def extract_modules(dRepo_path, settings_files, build_files)
    setting_path=get_settings_gradle_path(dRepo_path, settings_files);
    if(!setting_path.nil?)
        File.foreach("#{setting_path}") do |line| 
            line.scan(/'[^']+'|"[^\"]+"/).map {|m| m.strip.gsub(/('|")/,"")}.each do |m|
            module_path = "#{dRepo_path}" << m.gsub(/:/,"/")
            if is_application_module(module_path, build_files)
                pure_module = m.gsub(/:/,"")
                yield(pure_module)
            end
            end
        end
    else
        raise "settings.gradle or settings.gradle.kts  file not found in root of project."
    end
end

def runCommand(command)
    puts "@@[command] #{command}"
    status = nil
    stdout_str = nil
    stderr_str = nil

    Open3.popen3(command) do |stdin, stdout, stderr, wait_thr|
        stdout.each_line do |line|
            puts line
        end
        stdout_str = stdout.read
        stderr_str = stderr.read
        status = wait_thr.value
    end

    unless status.success?
        puts stderr_str
        raise stderr_str
    end
end

def get_build_variants(repo_path, aModule) 
    buildVariants = []
    runCommand("cd #{repo_path} && chmod +x ./gradlew")

    puts "@@[command] ./gradlew :#{aModule}:signingReport"
    Open3.popen3("./gradlew :#{aModule}:signingReport", :chdir=>repo_path) do |stdin, stdout, stderr, wait_thr|
        unless wait_thr.value.success?
            err = stderr.read
            puts err
            exit -1
        end
        while line = stdout.gets
            if line.start_with?("Variant") 
                puts line
                buildVariants << line.split(/:/).map { |word|  word.strip }.select do |word| 
                    not word.downcase.include?("variant") and  not word.match(/(.*UnitTest.*)|(.*AndroidTest.*)/)
                end
            end
        end
    end
    yield(buildVariants.reject { |ar| ar.empty? }.flatten)
end

def trim_to_relative_path(repo_path, absPath )
    return absPath.gsub("#{repo_path}",".")
end

def get_module_with_variants(repo_path, settings_files, build_gradle_files, platform_type)
    result = {}
    module_variant_arr = []
    all_projects = find_projects_root_path(repo_path, settings_files)

    if platform_type.downcase.eql? "reactnative"
        runCommand("cd #{repo_path} && if [ -f yarn.lock ]; then { yarn install && yarn list --depth=0; } else npm install; fi")
    end

    all_projects.each do |detected_path|
        extract_modules(detected_path, settings_files, build_gradle_files) do |aModule|
            modules_variants = {}
            modules_variants["modulePath"] = trim_to_relative_path(repo_path, detected_path)
            modules_variants["module"] = aModule
            get_build_variants(detected_path, aModule) do |variants|
                modules_variants["variants"] = variants
                module_variant_arr << modules_variants
            end
        end
    end
    result["modules"] = module_variant_arr
    return result
end

variants = get_module_with_variants(repo_path, settings_gradle_files, build_gradle_files, platform_type)

output_path = "#{temporary_path}/metadata.json"
File.open("#{output_path}", "w") { |file| file.write(variants.to_json) }

# Write Environment Variable
open(env_var_path, 'a') { |f|
  f.puts "AC_METADATA_OUTPUT_PATH=#{output_path}"
}

exit 0
