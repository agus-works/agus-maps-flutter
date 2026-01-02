### Implementation Notes

1. The main objective is to develop the plugin as explained in GUIDE.md
1. We will mutate `./GUIDE.md` as needed so that it continues to reflect the direction we want to take this development.
1. A `./thirdparty` folder must exist in the root of the repository. Create if not exists.
1. The `./scripts` folder in the root of the directory will be responsible for downloading dependencies. Dependencies that may come from other git repositories will be downloaded on to the thirdparty directory.
1. We will first focus on making the entire build workflow and example on android. Relevant directories are `./example/android` and `./android`. The solution must work as specified in `./GUIDE.md` on the `android` platform initially.
1. Do not poll terminal/cli MCP but instead run any arbitrary command as follows: `mycommand 2>&1 | tee ./output.log`. Then analyze the output.log making sure you're well aware of the file length before reading and strategically read the file by searching keywords relevant to analysis.
1. Do not commit automatically unless instructed specifically. And when commiting please use appropriate commit message.
1. When working on a specific target platform, make sure not to break other platforms! Be precise and surgical in updating `./patches`. You may create new patches as needed - but analyze if editing existing patch is more appropriate instead. Please update `./patches/comaps/README.md` when editing or adding patches! Analyze all patch changes and update the `./patches/comaps/README.md` as appropriate in detail with the same formatting as the other existing items.

### Thirdparty Patching Mechanism

**IMPORTANT:** The `./thirdparty/comaps` directory contains a git checkout of the CoMaps project with local modifications. These modifications are tracked via patch files in `./patches/comaps/`. Do not run patch update scripts at `./scripts` command automatically! Please update or create new patches. Always be precise, surgical, and anal about editing patches! Do not run scripts that will edit/modify all patches!

### Conventional Commits

The key words “MUST”, “MUST NOT”, “REQUIRED”, “SHALL”, “SHALL NOT”, “SHOULD”, “SHOULD NOT”, “RECOMMENDED”, “MAY”, and “OPTIONAL” in this document are to be interpreted as described in RFC 2119.

* Commits MUST be prefixed with a type, which consists of a noun, feat, fix, etc., followed by the OPTIONAL scope, OPTIONAL !, and REQUIRED terminal colon and space.
* The type feat MUST be used when a commit adds a new feature to your application or library.
* The type fix MUST be used when a commit represents a bug fix for your application.
* A scope MAY be provided after a type. A scope MUST consist of a noun describing a section of the codebase surrounded by parenthesis, e.g., fix(parser):
* A description MUST immediately follow the colon and space after the type/scope prefix. The description is a short summary of the code changes, e.g., fix: array parsing issue when multiple spaces were contained in string.
* A longer commit body MAY be provided after the short description, providing additional contextual information about the code changes. The body MUST begin one blank line after the description.
* A commit body is free-form and MAY consist of any number of newline separated paragraphs.
* One or more footers MAY be provided one blank line after the body. Each footer MUST consist of a word token, followed by either a :<space> or <space># separator, followed by a string value (this is inspired by the git trailer convention).
* A footer’s token MUST use - in place of whitespace characters, e.g., Acked-by (this helps differentiate the footer section from a multi-paragraph body). An exception is made for BREAKING CHANGE, which MAY also be used as a token.
* A footer’s value MAY contain spaces and newlines, and parsing MUST terminate when the next valid footer token/separator pair is observed.
* Breaking changes MUST be indicated in the type/scope prefix of a commit, or as an entry in the footer.
* If included as a footer, a breaking change MUST consist of the uppercase text BREAKING CHANGE, followed by a colon, space, and description, e.g., BREAKING CHANGE: environment variables now take precedence over config files.
* If included in the type/scope prefix, breaking changes MUST be indicated by a ! immediately before the :. If ! is used, BREAKING CHANGE: MAY be omitted from the footer section, and the commit description SHALL be used to describe the breaking change.
* Types other than feat and fix MAY be used in your commit messages, e.g., docs: update ref docs.
* The units of information that make up Conventional Commits MUST NOT be treated as case sensitive by implementors, with the exception of BREAKING CHANGE which MUST be uppercase.
* BREAKING-CHANGE MUST be synonymous with BREAKING CHANGE, when used as a token in a footer.