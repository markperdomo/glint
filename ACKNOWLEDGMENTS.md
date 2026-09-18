# Acknowledgments

Glint is inspired by Xee's quick folder browsing and keyboard-centered image viewing. The supplied Xee source identifies Dag Ågren as the original author and credits later work by CocoaBob, vit9696, and other contributors.

The old application's menu definitions, controller interfaces, source/decoder inventory, preferences, and tests were examined to understand behavior. This repository contains a new Swift implementation and new artwork; it does not bundle Xee's source files, resources, XADMaster, UniversalDetector, Carbon compatibility code, or old decoder libraries.

Apple's frameworks provide the platform image and graphics implementations. ZIP Deflate uses the macOS system zlib. Glint does not vendor a separate copy of zlib.
