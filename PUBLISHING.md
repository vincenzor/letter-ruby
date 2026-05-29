# Publishing `letterapp` (RubyGems)

Internal release notes. Not shipped with the gem.

## One-time setup

You need a RubyGems account with push access to the `letterapp` gem. Sign in
once so credentials land in `~/.gem/credentials`:

```bash
gem signin
```

## Cutting a release

```bash
# 1. Bump the version in lib/letterapp/version.rb (Letterapp::VERSION).
#    It is sent as the User-Agent so we can grep server logs for old clients.

# 2. Build the gem from the gemspec.
gem build letterapp.gemspec
#    -> produces letterapp-<version>.gem

# 3. (Optional) install it locally to smoke-test.
gem install ./letterapp-0.1.0.gem

# 4. Push to RubyGems.
gem push letterapp-0.1.0.gem

# 5. Commit the bump and push the tag.
git add lib/letterapp/version.rb
git commit -m "v0.1.0"
git tag v0.1.0
git push --follow-tags
```

`rubygems_mfa_required` is set in the gemspec metadata, so pushes require MFA.

## Versioning policy

While the wire format is pre-1.0:

- **patch** (`0.1.0 -> 0.1.1`) - bug fixes, doc tweaks, no surface change
- **minor** (`0.1.0 -> 0.2.0`) - new options/methods, behavior changes
- **major** (`0.x -> 1.0.0`) - only once the HTTP API and signatures are stable

## What lives where

- `lib/letterapp/client.rb` - the entire client. All public surface.
- `lib/letterapp/version.rb` - `Letterapp::VERSION` (single source of truth).
- `lib/letterapp.rb` - entry point; requires version + client.
- `letterapp.gemspec` - gem metadata and file list.
- `README.md` - RubyGems landing page.
- `LICENSE` - MIT.
