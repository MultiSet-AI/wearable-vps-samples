/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

package com.multiset.wearable.vps.ui

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import com.multiset.wearable.vps.R

@Composable
fun SharePhotoDialog(photo: Bitmap, onDismiss: () -> Unit, onShare: (Bitmap) -> Unit) {
  Dialog(onDismissRequest = onDismiss) {
    Card(
        modifier = Modifier.fillMaxWidth(0.9f).wrapContentHeight(),
        shape = RoundedCornerShape(16.dp),
    ) {
      Column(
          modifier = Modifier.fillMaxWidth().padding(16.dp),
          horizontalAlignment = Alignment.CenterHorizontally,
          verticalArrangement = Arrangement.spacedBy(16.dp),
      ) {
        Text(text = stringResource(R.string.photo_captured))

        Image(
            bitmap = photo.asImageBitmap(),
            contentDescription = stringResource(R.string.captured_photo),
            modifier = Modifier.fillMaxWidth().height(300.dp),
        )

        Button(onClick = { onShare(photo) }, modifier = Modifier.fillMaxWidth()) {
          Text(stringResource(R.string.share))
        }
      }
    }
  }
}
