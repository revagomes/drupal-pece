desc 'Generate deck from Travis CI and publish to GitHub Pages.'
task :travis do

  repo = 'https://github.com/revagomes/pece-distro.git'
  deploy_url = repo.gsub %r{https://}, "https://#{ENV['GH_TOKEN']}@"
  deploy_branch = 'master'
  rev = %x(git rev-parse HEAD).strip

  Dir.mktmpdir do |dir|
    temp_dir = File.join dir, 'pece'
    # sh './node_modules/.bin/gulp build'
    # source_code = '~/Sites/drupal-pece/build'
    sh 'pwd'
    sh 'ls'
    # fail "Build failed." unless Dir.exists? source_code

    # print "Repo: #{repo} /n"
    # print "Dir: #{dir} /n"
    # print "Destination: #{destination} /n"
    # sh "git clone --branch #{deploy_branch} #{repo} #{temp_dir}"
    # sh %Q(rsync -a --del --delete --exclude=".git" --exclude="sites/default/files" --exclude="sites/default/settings.php" --exclude="sites/default/settings.local.php" #{source_code} #{temp_dir})

    # Dir.chdir temp_dir do
    #   # setup credentials so Travis CI can push to GitHub
    #   verbose false do
    #     sh "git config user.name '#{ENV['GIT_NAME']}'"
    #     sh "git config user.email '#{ENV['GIT_EMAIL']}'"
    #   end
    #
    #   sh 'git add --all'
    #   sh "git commit -m 'Built from #{rev}'."
    #   verbose false do
    #     sh "git push -q #{deploy_url} #{deploy_branch}"
    #   end
    # end
  end
end
