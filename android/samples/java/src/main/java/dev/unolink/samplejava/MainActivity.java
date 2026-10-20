package dev.unolink.samplejava;

import android.app.Activity;
import android.os.Bundle;
import android.widget.TextView;

import java.math.BigDecimal;
import java.util.HashMap;
import java.util.Map;

import dev.unolink.LogLevel;
import dev.unolink.Unolink;
import dev.unolink.UnolinkDeepLink;
import dev.unolink.UnolinkOptions;

/** Calls every public SDK method from Java, so a Java-unfriendly API change fails to compile. */
public class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        Unolink.configure(this, "ulk_REPLACE_WITH_YOUR_KEY_000000000000");
        Unolink.configure(this, "ulk_REPLACE_WITH_YOUR_KEY_000000000000",
                new UnolinkOptions("https://api-uat.unolink.dev", LogLevel.DEBUG));
        Unolink.setDeferredDeepLinkListener(this::openDeepLink);

        Map<String, Object> properties = new HashMap<>();
        properties.put("level", 3);
        Unolink.track("level_up");
        Unolink.track("level_up", properties);
        Unolink.onboardingStep("goal");
        Unolink.onboardingStep("goal", 0);
        Unolink.onboardingStep("plan", 1, "v2");
        Unolink.onboardingSkipped("notifications", 2);
        Unolink.onboardingCompleted();
        Unolink.paywallViewed();
        Unolink.paywallViewed("onboarding");
        Unolink.paywallSkipped("feature_gate", properties);
        Unolink.signUp();
        Unolink.signUp("apple");
        Unolink.signIn();
        Unolink.signIn("google");
        Unolink.purchaseCancelled("pro_yearly");
        Unolink.purchaseFailed("pro_yearly", "card_declined");
        Unolink.setUserId("supabase-user-uuid");
        Unolink.setUserId(null);
        Unolink.trialStarted();
        Unolink.trialStarted("pro_yearly");
        Unolink.purchase(new BigDecimal("4.99"), "USD");
        Unolink.purchase(new BigDecimal("49.99"), "USD", "pro_yearly");
        Unolink.flush();
        Unolink.setEnabled(true);
        String installId = Unolink.getInstallId();
        String version = Unolink.VERSION;

        TextView view = new TextView(this);
        view.setText("Unolink " + version + "\nInstall ID: " + installId);
        setContentView(view);
    }

    private void openDeepLink(UnolinkDeepLink link) {
        String path = link.getDeepLink();
        Map<String, String> params = link.getParams();
        String slug = link.getLinkSlug();
        String clickId = link.getClickId();
    }
}
