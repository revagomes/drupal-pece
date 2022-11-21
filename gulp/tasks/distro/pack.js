var gulp = require('gulp');
var shell = require('shelljs');
var fs = require('fs');

var cwd = process.cwd();
var kwEnvConfigFile = cwd + '/cnf/environment';
var repo = 'https://github.com/PECE-project/pece-distro.git';
var commitMessage = 'New release based on master of development repository.';

gulp.task('distro:pack', gulp.series('distro:prepare'), function (done) {

  shell.cd('distro');
  shell.exec('git add -A');
  // shell.exec('git commit -m "' + commitMessage + '"');
  //shell.exec('git push ' + repo + ' master');
  done();
});
