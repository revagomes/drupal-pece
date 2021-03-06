
describe('License', function() {
  beforeEach(function() {
    AuthenticationPage.logout();
    AuthenticationPage.login(browser.params.admin.user, browser.params.admin.password);
  });

  it('check the field_pece_license presence and its default value for Artifact content type', function () {
    PeceArtifactPage.get();
    expect(PeceArtifactPage.licenseField.isPresent()).toBe(true);
    expect(PeceArtifactPage.licenseFieldDefaultValue.getText()).toEqual('Attribution, Share Alike CC BY-SA');
  });

  // @TODO: I think it could be in another file, since this is not directly related with Licence.
  it('can inherit Artifact\'s fields', function() {
    AddTypesPage.get();
    AddTypesPage.inheritanceLink.click();
    AddTypesPage.inheritanceCheckBox.click();
    // @TODO: Today we already have two more artifacts with the word Artifact, beyond the one that we need
    // to check, like Artifact - Image and Artifact - PDF Document, so, this is a not reliable test.
    expect(AddTypesPage.bundleInheritParentSelect.getText()).toContain('Artifact');
  });
});
