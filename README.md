# aianalyse

[KOReader](https://koreader.rocks/user_guide/) plugin that allows for text analysis using LLMs. 

![text analysis](https://dump-show-cap.s3.ap-southeast-2.amazonaws.com/output.gif)

## Supported LLM Providers

* Anthropic 🤖
* DeepSeek 🐋

## Installation

### Download the plugin

Go to [releases](https://github.com/oscargolding/aianalyse/releases/tag/latest) and download the latest release of the plugin.

### Install on KOReader device

For below, `[koreader]/` means the folder that KOReader is installed to.

* On Kobo: `/.adds/koreader/`
* On Kindle: `/koreader`
* On Android: koreader at the root of your onboard storage

Open the zip file, and install `aianalyse.koplugin` to `[koreader]/plugins`.

### Enable the plugin

Eject your device. Show the top menu for KOReader. 
Tap the wrench icon and "More tools" -> "Plugin management" -> enable (check) "AI Analyse". Tap "Restart Now.".

### Input LLM API Keys

When a book is open, select "More tools" -> "AI Analyse" -> "Settings".

You will be given an option to enter an API key for either Anthropic or DeepSeek.

