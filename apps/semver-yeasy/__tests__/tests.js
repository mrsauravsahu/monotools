// tests/demo.js
import { test } from 'uvu';
import * as assert from 'uvu/assert';
import { exec } from 'child-process-promise';
import  testConfig from './config.json' assert { type: "json" };

testConfig.tests.forEach(t => {
  test(t.name, async () => {
    const currTestWorkspace = `tmp_${t.name}`

    await exec(`mkdir -p ${currTestWorkspace}`)
    await exec(`
    git config --global user.email 'example@example.com'
    git config --global user.name 'Example'
    git init
    mkdir -p .cicd/common
    cp ../gitversion.yml ./.cicd/common\"
    `, {
      cwd: currTestWorkspace
    })

    for (var setupStep of t.repoSetup) {
      await exec(setupStep, {cwd:currTestWorkspace});
    }

    const data = await exec('bash ../apps/semver-yeasy/semver-yeasy.sh calculate-version')

    assert.equal(data.stdout, 'lel')
    await exec(`rm -r ${currTestWorkspace}`)
  })
})

test.run();
