var gulp = require('gulp');
var shell = require('shelljs');
var fs = require('fs');

var cwd = process.cwd();
var repo = 'https://github.com/revagomes/pece-distro.git';

gulp.task('pack-distro', function () {
  // Clone distro repository.
  fs.stat('distro', function(err) {
    if(err == null) {
      shell.exec('rm -rf distro');
      packDistroCallback();
    }
    else {
      packDistroCallback();
    }
  });

});

var packDistroCallback = function () {
  shell.exec('git clone ' + repo + ' distro');

  // Update distro repository with new build.
  shell.exec('cp -a build/* distro/');
  shell.cd('distro');
  shell.exec('git add .');

  var currentHead = shell.exec('git rev-parse HEAD').trim();
  var commitMessage = 'Added new build from ' + currentHead + ' commit of development repository.'
  var deployUrl = repo.replace('http://', `http://${process.env.GH_TOKEN}@`);

  shell.exec(`git config user.name '${process.env.GIT_NAME}'`);
  shell.exec(`git config user.email '${process.env.GIT_EMAIL}'`);
  shell.exec(`git commit -m "${ commitMessage }"`);
  shell.exec(`git push -q ${deployUrl} master`);
}
