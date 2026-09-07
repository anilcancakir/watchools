<?php

namespace Tests\Unit\Models;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Covers the User model's casts and hidden attributes.
 *
 * Both are declared as data rather than code, so a typo in either is invisible
 * to the analyzer and only shows up as a plaintext password in an API response
 * or a string where a Carbon instance was expected.
 */
class UserTest extends TestCase
{
    use RefreshDatabase;

    public function test_it_hashes_the_password_on_assignment(): void
    {
        $user = User::factory()->create(['password' => 'plain-text-secret']);

        $this->assertNotSame('plain-text-secret', $user->password);
        $this->assertTrue(password_verify('plain-text-secret', $user->password));
    }

    public function test_it_hides_the_password_and_remember_token_from_arrays(): void
    {
        $user = User::factory()->create();

        $serialised = $user->toArray();

        $this->assertArrayNotHasKey('password', $serialised);
        $this->assertArrayNotHasKey('remember_token', $serialised);
    }

    public function test_it_casts_the_email_verification_timestamp_to_a_date(): void
    {
        $user = User::factory()->create(['email_verified_at' => '2026-09-07 12:00:00']);

        $this->assertInstanceOf(\Illuminate\Support\Carbon::class, $user->email_verified_at);
        $this->assertSame('2026-09-07', $user->email_verified_at->toDateString());
    }
}
