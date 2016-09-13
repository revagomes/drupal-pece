var gulp = require('gulp');
var shell = require('shelljs');

var cwd = process.cwd();
var repo = 'https://github.com/revagomes/pece-distro.git';

gulp.task('pack-distro', function () {
  // Clone distro repository.
  shell.exec('rm -r distro');
  shell.exec('git clone ' + repo + ' distro');

  // Build Drupal project.
  shell.exec('drush kw-s');
  shell.exec('drush kw-b');

  // Update distro repository with new build.
  shell.exec('cp -r build/* distro/');
  shell.cd('distro');
  shell.exec('pwd');
  shell.exec('git add .');
  shell.exec('git commit -m "Added new build."');
});
