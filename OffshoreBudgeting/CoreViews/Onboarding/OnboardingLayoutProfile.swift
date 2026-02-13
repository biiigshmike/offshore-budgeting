//
//  OnboardingLayoutProfile.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/13/26.
//

import SwiftUI
import UIKit

struct OnboardingLayoutProfile {

    let horizontalPadding: CGFloat

    static func resolve(
        containerWidth _: CGFloat,
        horizontalSizeClass: UserInterfaceSizeClass?,
        dynamicTypeSize: DynamicTypeSize
    ) -> OnboardingLayoutProfile {
        let idiom = UIDevice.current.userInterfaceIdiom
        let isLargeDeviceClass = horizontalSizeClass == .regular || idiom == .pad || idiom == .mac
        let isAccessibilitySize = dynamicTypeSize.isAccessibilitySize

        let baseHorizontalPadding: CGFloat = isLargeDeviceClass ? 28 : 18
        let horizontalPadding = isAccessibilitySize ? (baseHorizontalPadding + 8) : baseHorizontalPadding

        if isLargeDeviceClass {
            return OnboardingLayoutProfile(
                horizontalPadding: horizontalPadding
            )
        }

        return OnboardingLayoutProfile(
            horizontalPadding: horizontalPadding
        )
    }
}
