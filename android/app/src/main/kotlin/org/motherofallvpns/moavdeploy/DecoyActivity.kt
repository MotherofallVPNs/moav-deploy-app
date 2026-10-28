package org.motherofallvpns.moavdeploy

/**
 * The activity behind the Notes launcher alias. Same Flutter engine and Dart
 * code as [MainActivity]; it exists only so the manifest can give the
 * disguised launch its own plain window theme (no MoaV splash) and label.
 */
class DecoyActivity : MainActivity()
