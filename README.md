# Vest Silo

Vest Silo is a standalone macOS widget for tracking your Vest Markets positions. The collapsed bar shows your open position count and combined unrealized P&L. Expand it to see entry and current mark prices, estimated fail prices, and account drawdown in one row per account.

## Get started

1. Download or clone this repository on a Mac. You’ll need macOS 13 or newer and Apple’s Command Line Tools. If they aren’t installed, run `xcode-select --install` first.
2. Open Terminal in the project folder and run `./build.sh`.
3. Open **Vest Silo.app** from the project folder.
4. Choose **Vest Silo → Connect to Vest…** in the menu bar and sign in on the Vest page. After connecting, you can close that window and use the widget.

Vest Silo uses a separate WebKit session and requires no browser extension. On macOS 14 or newer, the app attempts to restore its saved session on launch. If Vest expires that session, open **Connect to Vest…** again.

## Make it yours

Open the gear in the widget or choose **Vest Silo → Settings…**. Set the width, height, opacity, font size, and screen position. Enable **Tuck away when collapsed** to keep just the compact status strip on screen. Click the strip to expand it again.

To try the layout with sample positions before signing in, run `open -na "Vest Silo.app" --args --demo`.

## Privacy

The widget reads account and position data from Vest. The embedded browser manages sign-in locally on your Mac. This repository contains source code and build assets only. Vest Silo is an unofficial project.
