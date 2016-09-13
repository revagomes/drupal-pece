var gulp = require('gulp');
var shell = require('shelljs');

var cwd = process.cwd();
var repo = 'https://github.com/revagomes/pece-distro.git';

gulp.task('pack-distro', function () {
  shell.exec('rm -r distro');
  shell.exec('git clone ' + repo + ' distro');
  shell.exec('drush kw-s');
  shell.exec('drush kw-b');
});
