/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

package com.multiset.wearable.vps.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.Image
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.multiset.wearable.vps.BuildConfig
import com.multiset.wearable.vps.R
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.cos
import kotlin.math.sin
import kotlin.random.Random

private data class Particle(
    var x: Float,
    var y: Float,
    var velocityX: Float,
    var velocityY: Float,
    var radius: Float,
    var alpha: Float,
    var color: Color,
    var life: Float = 1f,
    var decay: Float = 0.01f,
)

@Composable
fun SplashScreen(
    onSplashComplete: () -> Unit,
    modifier: Modifier = Modifier,
) {
    // Animation values
    val logoScale = remember { Animatable(0f) }
    val logoAlpha = remember { Animatable(0f) }
    val textAlpha = remember { Animatable(0f) }
    val versionAlpha = remember { Animatable(0f) }

    // Particle system
    val particles = remember { mutableStateListOf<Particle>() }

    // Infinite rotation for glow effect
    val infiniteTransition = rememberInfiniteTransition(label = "glow")
    val glowRotation by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(
            animation = tween(3000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "glowRotation",
    )

    // Pulsing glow
    val glowScale by infiniteTransition.animateFloat(
        initialValue = 1f,
        targetValue = 1.2f,
        animationSpec = infiniteRepeatable(
            animation = tween(1000, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "glowScale",
    )

    // Launch animations and spawn particles
    LaunchedEffect(Unit) {
        // Initialize particles
        repeat(50) {
            particles.add(createParticle())
        }

        // Logo scale and fade in
        launch {
            logoScale.animateTo(
                targetValue = 1f,
                animationSpec = tween(600, easing = FastOutSlowInEasing),
            )
        }
        launch {
            logoAlpha.animateTo(
                targetValue = 1f,
                animationSpec = tween(500),
            )
        }

        // Text fade in with delay
        delay(300)
        launch {
            textAlpha.animateTo(
                targetValue = 1f,
                animationSpec = tween(400),
            )
        }

        // Version fade in
        delay(200)
        launch {
            versionAlpha.animateTo(
                targetValue = 1f,
                animationSpec = tween(300),
            )
        }

        // Update particles continuously
        launch {
            while (true) {
                particles.forEachIndexed { index, particle ->
                    particle.x += particle.velocityX
                    particle.y += particle.velocityY
                    particle.life -= particle.decay
                    particle.alpha = (particle.life * 0.8f).coerceIn(0f, 1f)

                    // Reset dead particles
                    if (particle.life <= 0) {
                        particles[index] = createParticle()
                    }
                }
                delay(16) // ~60fps
            }
        }

        // Wait for splash duration then complete
        delay(1500)
        onSplashComplete()
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(
                Brush.radialGradient(
                    colors = listOf(
                        Color(0xFF1a1a2e),
                        Color(0xFF16213e),
                        Color(0xFF0f0f23),
                    ),
                    radius = 1500f,
                ),
            ),
        contentAlignment = Alignment.Center,
    ) {
        // Particle layer
        Canvas(modifier = Modifier.fillMaxSize()) {
            particles.forEach { particle ->
                drawCircle(
                    color = particle.color.copy(alpha = particle.alpha),
                    radius = particle.radius,
                    center = Offset(particle.x, particle.y),
                )
            }
        }

        // Glow effect behind logo
        Canvas(
            modifier = Modifier
                .size(200.dp)
                .scale(glowScale),
        ) {
            val center = Offset(size.width / 2, size.height / 2)
            val radius = size.minDimension / 2

            // Multiple rotating gradient glows
            for (i in 0..2) {
                val angle = Math.toRadians((glowRotation + i * 120).toDouble())
                val glowOffset = Offset(
                    center.x + (radius * 0.3f * cos(angle)).toFloat(),
                    center.y + (radius * 0.3f * sin(angle)).toFloat(),
                )
                drawCircle(
                    brush = Brush.radialGradient(
                        colors = listOf(
                            AppColor.DeepBlue.copy(alpha = 0.4f),
                            AppColor.DeepBlue.copy(alpha = 0.1f),
                            Color.Transparent,
                        ),
                        center = glowOffset,
                        radius = radius * 1.2f,
                    ),
                    radius = radius * 1.5f,
                    center = center,
                )
            }
        }

        // Main content
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.padding(32.dp),
        ) {
            // App Icon with animations
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .scale(logoScale.value)
                    .alpha(logoAlpha.value),
            ) {
                // Outer glow ring
                Canvas(modifier = Modifier.size(160.dp)) {
                    drawCircle(
                        brush = Brush.radialGradient(
                            colors = listOf(
                                AppColor.DeepBlue.copy(alpha = 0.4f),
                                AppColor.DeepBlue.copy(alpha = 0.1f),
                                Color.Transparent,
                            ),
                        ),
                        radius = size.minDimension / 2,
                    )
                }

                // The multiset rayban logo
                Image(
                    painter = painterResource(id = R.drawable.multiset_rayban),
                    contentDescription = "App Icon",
                    modifier = Modifier
                        .size(130.dp)
                        .clip(CircleShape),
                    contentScale = ContentScale.Crop,
                )
            }

            Spacer(modifier = Modifier.height(32.dp))

            // App Name
            Text(
                text = "Multiset Wearable VPS",
                fontSize = 32.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White,
                modifier = Modifier.alpha(textAlpha.value),
            )

            Spacer(modifier = Modifier.height(8.dp))

            // Tagline
            Text(
                text = "Spatial AI for the real world.",
                fontSize = 16.sp,
                fontWeight = FontWeight.Normal,
                color = Color.White.copy(alpha = 0.7f),
                modifier = Modifier.alpha(textAlpha.value),
            )
        }

        // Version at bottom
        Text(
            text = "Version ${BuildConfig.VERSION_NAME}",
            fontSize = 12.sp,
            color = Color.White.copy(alpha = 0.5f),
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 48.dp)
                .alpha(versionAlpha.value),
        )
    }
}

private fun createParticle(): Particle {
    val screenWidth = 1080f
    val screenHeight = 2400f
    val angle = Random.nextFloat() * 360f
    val speed = Random.nextFloat() * 2f + 0.5f
    val colors = listOf(
        AppColor.DeepBlue,
        Color(0xFF4A90D9),
        Color(0xFF64B5F6),
        Color(0xFF90CAF9),
        AppColor.Green.copy(alpha = 0.7f),
    )

    return Particle(
        x = Random.nextFloat() * screenWidth,
        y = Random.nextFloat() * screenHeight,
        velocityX = cos(Math.toRadians(angle.toDouble())).toFloat() * speed,
        velocityY = sin(Math.toRadians(angle.toDouble())).toFloat() * speed,
        radius = Random.nextFloat() * 4f + 2f,
        alpha = Random.nextFloat() * 0.6f + 0.2f,
        color = colors[Random.nextInt(colors.size)],
        life = Random.nextFloat() * 0.5f + 0.5f,
        decay = Random.nextFloat() * 0.01f + 0.005f,
    )
}
