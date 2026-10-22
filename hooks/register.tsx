import type { Register } from 'claude-code'

// Ships the pill status line as assets/statusline.ps1; `/pills` copies it to
// ~/.claude/statusline.ps1 (keeping a backup) and says what settings.json needs.
export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'pills',
      description: 'Install the rounded pill status line (~/.claude/statusline.ps1)',
    })
    return next(e)
  })

  on('command.run', { command: 'pills' }, async $ => {
    const home = await $.env.get('USERPROFILE')
    if (!home) return { text: 'USERPROFILE is not set; cannot find ~/.claude.' }
    const target = `${home}/.claude/statusline.ps1`.replaceAll(String.fromCharCode(92), '/')
    const script = await $.fs.read(`${$.plugin.root}/assets/statusline.ps1`)
    if (await $.fs.exists(target)) {
      await $.fs.write(`${target}.bak-pills`, await $.fs.read(target))
    }
    await $.fs.write(target, script)
    const cmd = `pwsh -NoProfile -File ${target}`
    return {
      text: `Installed ${target} (previous copy saved as .bak-pills). settings.json needs: "statusLine": { "type": "command", "command": "${cmd}" }. Needs a Nerd Font.`,
    }
  })
}
