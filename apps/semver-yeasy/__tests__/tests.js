import { test as it } from 'uvu';
import * as assert from 'uvu/assert';
import { exec } from 'child-process-promise';
import testConfig from './config.json' assert { type: "json" };

var { ROOT_TEST_FOLDER } = process.env;
await exec(`rm -rf ${ROOT_TEST_FOLDER}/test-workspaces || true`)

testConfig.tests.forEach(currentTest => {
  const currentTestWorkspace = `test-workspaces/tmp_${currentTest.name}`
  const currentTestGitRepoPath = `test-workspaces/tmp_${currentTest.name}/repo`
  const currentTestSourceCodePath = `test-workspaces/tmp_${currentTest.name}/repo/src`
  it.before(async () => {
    await exec(`
    mkdir -p ${ROOT_TEST_FOLDER}/${currentTestWorkspace}
    mkdir -p ${ROOT_TEST_FOLDER}/${currentTestGitRepoPath}
    mkdir -p ${ROOT_TEST_FOLDER}/${currentTestSourceCodePath}
    `)
    await exec(`
    cd ${ROOT_TEST_FOLDER}
    cd ..
    SEMVER_YEASY_ROOT_DIRECTORY=\`pwd\`

    cd __tests__
    cd ${currentTestGitRepoPath}

    git config --global user.email 'example@example.com'
    git config --global user.name 'Example'
    git init
    `)

    for (var setupStep of currentTest.repoSetup) {
      await exec(setupStep, { cwd: currentTestWorkspace });
    }
  })

  it(`${currentTest.name} - changed services`, async () => {
    const data = await exec(`GITHUB_OUTPUT=\'${currentTestWorkspace}/output.changed-services.txt\' bash ../semver-yeasy.sh changed`)

    assert.equal(data.stdout, `lul`)
  })

  it(`${currentTest.name} - PR Description`, async () => {
    const data = await exec(`GITHUB_OUTPUT=\'${currentTestWorkspace}/output.pr-description.txt\' bash ../semver-yeasy.sh calculate-version`)

    assert.equal(data.stdout, `Monotools: semver-yeasy
"## impact surface\\\\nNo services changed\\\\n"
`)
  })

  // it.after(async () => await exec(`rm -r ${currentTestWorkspace}`))
})

it.run();
