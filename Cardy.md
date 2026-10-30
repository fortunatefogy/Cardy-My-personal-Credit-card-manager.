Project Prompt: CardWise AI — Smart Credit Card Manager for Android

1. Project Overview

Build a complete, production-quality Android application named CardWise AI, designed primarily for Indian users who own multiple credit cards.

The app should allow users to manage all their credit cards in one place, automatically discover current credit card offers from the internet, compare card benefits, and use an AI-powered chatbot to identify the best card for any purchase.

I personally manage approximately 13 credit cards, so the app must support multiple cards without arbitrary limits.

Important exclusions: Do not implement payment tracking, billing-cycle tracking, due-date reminders, EMI payment reminders, or payment notifications.

This is a functional application, not just a UI prototype. Implement the frontend, backend, database, APIs, AI integration, offer discovery, and error handling.

2. Recommended Technology Stack

Frontend: Flutter and Dart.
State management: GetX.
Backend and database: Supabase or Appwrite.
Authentication: Secure email authentication, with optional biometric app locking.
AI chatbot: An LLM API accessed through a secure backend.
Background offer discovery: Scheduled backend jobs or serverless functions.
Local caching: Appropriate local database with secure storage for sensitive information.
Notifications: No payment-related notifications. Do not add offer push notifications unless explicitly requested later.
Architecture: Feature-based, modular, maintainable and scalable.

Inspect the existing project before modifying it. Reuse existing architecture and dependencies where appropriate instead of rebuilding unnecessarily.

3. Core Features

A. Home Dashboard

Create a premium dashboard containing:

Total number of saved cards.
Horizontally scrollable credit card carousel.
Recently discovered offers.
Best offers matching the user's cards.
Quick action to find the best card for a purchase.
Quick action to add a new card.
Search functionality.
Last successful offer refresh time.
Loading, empty, offline and error states.

Do not display payment due dates, bill amounts, payment schedules or reminders.

B. My Cards — Complete Card Management

Users must be able to add, view, edit, deactivate, reactivate and delete credit cards.

Provide a prominent + Add New Card button.

Add New Card

Support two methods:

Method 1: Search the card catalogue

Search by bank, issuer or credit card name.
Show matching card variants.
Select a card to prefill known information.
Retrieve available card details from a maintained card catalogue.
Allow the user to edit prefilled information.
Clearly distinguish verified bank-published information from estimates and user-entered overrides.

Method 2: Manual entry

Bank or issuer name.
Credit card name and variant.
Card network: Visa, Mastercard, RuPay, American Express or other.
Card nickname.
Annual fee and fee-waiver conditions.
Cashback percentage and applicable spending categories.
Reward points earned per eligible spend.
Estimated monetary value of reward points.
Reward redemption restrictions.
Welcome benefits.
Airport lounge access and eligibility requirements.
Fuel surcharge benefits.
Dining, travel, shopping and entertainment benefits.
Spending thresholds and monthly or transaction caps.
Excluded transactions and merchant categories.
Known offer eligibility conditions.
Optional notes.

Support custom banks and unlisted cards.

Allow multiple cards from the same bank, including different variants.

Card Details Page

Display:

Card artwork and bank logo.
Card name, network and nickname.
Rewards and benefits.
Annual fee and waiver conditions.
Relevant active offers.
Spending-category performance.
Edit, deactivate and delete actions.

Never require the full card number. If an optional identifier is needed, allow only a nickname or a masked identifier. Never store CVV, PIN or OTP.

C. Automatic Internet Offer Discovery

This is a major feature and must be implemented as a genuine data pipeline, not static sample data.

Discover publicly available credit card offers from permitted online sources, prioritizing:

Official Indian bank websites.
Official card issuer offer pages.
Amazon India and Flipkart.
Electronics, fashion and lifestyle retailers.
Travel booking websites.
Restaurants and entertainment merchants.
Other relevant merchants with published card offers.

Use official APIs, permitted feeds, structured public pages or compliant scraping where allowed by source terms. Do not bypass authentication, CAPTCHAs, rate limits or access controls.

Offer Data Model

Each offer should include:

Offer title and description.
Merchant and applicable category.
Eligible bank and card variants.
Eligible payment method.
Discount type: instant discount, cashback, reward points, percentage discount or other.
Discount percentage and maximum discount.
Minimum transaction value.
Maximum eligible spend, if applicable.
Start and expiry dates, when published.
Online, offline or both.
EMI or non-EMI eligibility.
Exclusions and terms.
Official source URL.
Source name.
Last-checked timestamp.
Verification status.
Active, expired, unavailable or needs-review status.

Automatic Refresh

Implement scheduled backend refresh jobs approximately every six hours, where practical.

Also:

Refresh stale offers on app launch.
Recheck relevant offers when the AI receives a purchase query.
Cache the last successful results.
Deduplicate offers discovered across multiple sources.
Update changed offer terms.
Mark expired offers appropriately.
Handle source failures without deleting valid cached results.
Record refresh errors and source health.
Respect website terms, rate limits and robots directives where applicable.

Do not claim an offer is live or verified unless its status is supported by sufficiently recent source data. Display when it was last checked.

If an offer source cannot be accessed automatically, show the last known information with an appropriate warning or provide a link to the official source. Never invent offers.

D. AI-Powered Best Card Finder

Build an intelligent chatbot that can use the user's saved card profiles, card reward rules, and current offer database.

Example questions:

Which card should I use to buy a ₹40,000 phone?
Which of my cards gives the best Amazon discount today?
Which card is best for Flipkart purchases?
What is the best card for dining?
Which card should I use for an airline ticket?
Compare my cards for a ₹20,000 purchase.
Is the current instant discount better than my normal cashback?
Which of my cards offers lounge access?
Find active offers available on my cards.
Which card provides the highest effective savings for this product?

Purchase Input

The assistant should understand:

Product or merchant.
Purchase amount.
Purchase category.
Online or offline payment.
Applicable payment method.
EMI preference, if relevant.
User-selected card restrictions.

Ask a short follow-up question only when essential information is missing.

Recommendation Engine

Implement deterministic calculations for financial results. Use AI to interpret user questions, explain results and ask clarifying questions, but do not rely on the LLM alone for arithmetic.

For every eligible card, calculate:

Applicable instant discount.

Cashback earned.

Reward points earned.

Estimated monetary value of reward points.

Discount caps and spending thresholds.

Relevant transaction or redemption fees.

Net effective purchase cost.

Estimated total savings.

Use the following general calculation:

Net effective cost = Purchase amount - applicable discounts - estimated realizable reward value + relevant incremental fees.

Avoid double-counting overlapping rewards, cashback or discounts. Apply offer-specific eligibility conditions and caps. Do not count benefits that cannot be verified or reasonably valued as guaranteed savings.

Rank eligible cards by estimated net savings. Include a breakdown explaining why the winning card is recommended.

For each recommendation, show:

Recommended card.
Estimated instant discount.
Estimated cashback and reward value.
Fees or relevant limitations.
Net effective cost.
Comparison with the next-best card.
Offer source and validity.
Confidence and verification status.

If there is insufficient data, clearly state the uncertainty rather than inventing a result.

E. Card Comparison

Allow users to select two or more cards and compare:

Annual fees.
Cashback rates.
Reward earning rates.
Reward redemption value.
Lounge access.
Dining and travel benefits.
Fuel benefits.
Shopping offers.
Spending caps.
Exclusions.
Best-fit spending categories.

Support both general comparisons and purchase-specific comparisons.

F. Rewards Insights

Provide useful insights based on saved card benefit rules and optional manually entered purchases.

Examples:

Best saved card for groceries.
Best card for online shopping.
Best card for travel.
Best card for dining.
Estimated reward value for a planned purchase.
Categories where another saved card might provide greater value.

Do not automatically access bank accounts or import transactions without explicit authorization and a suitable supported integration.

G. Search and Filters

Implement global search for:

Saved cards.
Card variants.
Active offers.
Banks and merchants.
Purchase categories.
Specific card benefits.

Offer filters for bank, merchant, discount type, expiry, minimum spend, eligible card and payment type.

4. UI/UX and Visual Design

Create a premium, modern fintech interface.

Color Palette

Use:

Deep black or charcoal: #121212
Dark surface: #1C1C1E
Bright orange: #FF7A00
White: #FFFFFF
Muted grey: #A1A1AA
Green for verified savings or positive results.
Red for expired or invalid offers.

Use orange as the primary accent, with white text and subtle grey surfaces.

Design Principles

Modern Material 3 design.
Premium dark theme.
Rounded cards and clean spacing.
Attractive credit card artwork.
Subtle glassmorphism only where readability remains excellent.
Smooth transitions and animations.
Clear icons for each feature.
Responsive layouts for different Android screen sizes.
Accessible contrast and readable typography.
Skeleton loading states and polished empty states.
Avoid excessive gradients, unnecessary background images and visual clutter.

Bottom Navigation

Create four main navigation tabs:

Home — Dashboard and quick actions.

My Cards — Saved cards, card catalogue and add-card functionality.

Offers — Discovered offers, filters and offer details.

AI Assistant — Purchase recommendations and conversational help.

Card comparison and rewards insights can be accessible from the relevant screens.

5. Database and Backend

Design a clean schema for:

User profiles.
Card catalogue.
User-owned cards.
Card benefit rules.
Reward valuation rules.
Offers.
Offer eligibility.
Offer sources.
Refresh history.
Chat sessions.
Chat messages.
Optional manually entered purchases.

Implement appropriate foreign keys, indexes, data validation and access controls.

Each user must only be able to access their own saved cards and private data. Use row-level security when supported.

Store public card catalogue and offer information separately from private user records.

Implement backend services for:

Card catalogue search.
Card creation and updates.
Offer discovery and normal