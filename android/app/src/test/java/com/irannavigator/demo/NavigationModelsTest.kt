package com.irannavigator.demo

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class NavigationModelsTest {
    @Test
    fun travelModesExposeTheSameCostingPolicy() {
        assertEquals(listOf("auto"), TravelMode.CAR.costingCandidates())
        assertEquals(listOf("motorcycle", "motor_scooter"), TravelMode.MOTORCYCLE.costingCandidates())
        assertEquals(listOf("pedestrian"), TravelMode.WALKING.costingCandidates())
    }

    @Test
    fun startAndMergeManeuversHaveDistinctPersianInstructions() {
        assertEquals(
            "از سمت راست حرکت را آغاز کنید",
            PersianInstructionFormatter.instruction(2, "")
        )
        assertEquals(
            "از سمت چپ حرکت را آغاز کنید",
            PersianInstructionFormatter.instruction(3, "")
        )
        assertEquals(
            "از سمت راست به مسیر اصلی ادغام شوید",
            PersianInstructionFormatter.instruction(37, "")
        )
        assertEquals(
            "از سمت چپ به مسیر اصلی ادغام شوید",
            PersianInstructionFormatter.instruction(38, "")
        )
    }

    @Test
    fun streetNameIsIncludedForStreetTurns() {
        assertEquals(
            "به راست بپیچید و وارد ولیعصر شوید",
            PersianInstructionFormatter.instruction(10, "ولیعصر")
        )
    }

    @Test
    fun distanceUsesRoundedPersianDigits() {
        assertEquals("۱٫۵ کیلومتر", PersianInstructionFormatter.distance(1500.0))
        assertEquals("۲۶ متر", PersianInstructionFormatter.distance(25.6))
    }

    @Test
    fun routeResultCanReportMotorcycleFallback() {
        val result = RouteResult(
            points = listOf(NavPoint(35.7, 51.4), NavPoint(35.71, 51.39)),
            maneuvers = emptyList(),
            distanceKm = 1.0,
            durationSeconds = 120.0,
            usedMotorcycleFallback = true
        )
        assertTrue(result.usedMotorcycleFallback)
    }
}
