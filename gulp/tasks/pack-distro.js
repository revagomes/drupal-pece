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
  var commitMessage = 'Added new release based on master of development repository.'

  shell.exec(`git commit -m "${ commitMessage }"`);
  shell.exec(`git push -q ${repo} master`);
}
