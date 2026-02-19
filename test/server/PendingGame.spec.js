import PendingGame from '../../server/pendinggame.js';
import User from '../../server/models/User.js';

describe('PendingGame', function () {
    beforeEach(function () {
        this.owner = new User({ username: 'test1' });
        this.game = new PendingGame(this.owner, 'development', { spectators: true });
    });

    describe('block list functionality', function () {
        beforeEach(function () {
            this.blockedUser = new User({ username: 'IHarassPeople' });
            this.owner.block(this.blockedUser);
        });

        it('should not allow a blocked user to join the game', function () {
            this.game.join(2, this.blockedUser, '', () => true);
            expect(Object.values(this.game.getPlayersAndSpectators())).not.toContain(
                jasmine.objectContaining({ user: this.blockedUser })
            );
        });

        it('should not allow a blocked user to watch the game', function () {
            this.game.watch(2, this.blockedUser, '', () => true);
            expect(Object.values(this.game.getPlayersAndSpectators())).not.toContain(
                jasmine.objectContaining({ user: this.blockedUser })
            );
        });
    });

    describe('isVisibleFor', function () {
        beforeEach(function () {
            this.otherUser = new User({ username: 'foo' });
        });

        it('should return true by default', function () {
            expect(this.game.isVisibleFor(this.otherUser)).toBe(true);
        });

        describe('when the owner blocks the other user', function () {
            beforeEach(function () {
                this.owner.block(this.otherUser);
            });

            it('should return false', function () {
                expect(this.game.isVisibleFor(this.otherUser)).toBe(false);
            });
        });

        describe('when the other user blocks the owner', function () {
            beforeEach(function () {
                this.otherUser.block(this.owner);
            });

            it('should return false', function () {
                expect(this.game.isVisibleFor(this.otherUser)).toBe(false);
            });
        });

        describe('when a joined player blocks the other user', function () {
            beforeEach(function () {
                let playerUser = new User({ username: 'player' });
                playerUser.block(this.otherUser);
                this.game.addPlayer(1, playerUser);
            });

            it('should return false', function () {
                expect(this.game.isVisibleFor(this.otherUser)).toBe(false);
            });
        });
    });

    describe('getSummary', function () {
        beforeEach(function () {
            this.player = new User({ username: 'player1' });
            this.game.addPlayer(1, this.player);
            this.game.started = true;
            this.game.gamePrivate = false;

            // Set up faction and agendas on the player
            let playerEntry = this.game.players[this.player.username];
            playerEntry.faction = { cardData: { code: 'stark' } };
            playerEntry.agendas = [{ cardData: { code: 'fealty' } }];
        });

        describe('when isAuthenticated is true', function () {
            it('should include faction and agenda codes', function () {
                let summary = this.game.getSummary(undefined, true);
                let playerSummary = summary.players[this.player.username];

                expect(playerSummary.faction).toBe('stark');
                expect(playerSummary.agendas).toEqual(['fealty']);
            });
        });

        describe('when isAuthenticated is false', function () {
            it('should not include faction or agenda codes', function () {
                let summary = this.game.getSummary(undefined, false);
                let playerSummary = summary.players[this.player.username];

                expect(playerSummary.faction).toBeUndefined();
                expect(playerSummary.agendas).toEqual([undefined]);
            });
        });

        describe('when isAuthenticated is not provided (default)', function () {
            it('should include faction and agenda codes by default', function () {
                let summary = this.game.getSummary();
                let playerSummary = summary.players[this.player.username];

                expect(playerSummary.faction).toBe('stark');
                expect(playerSummary.agendas).toEqual(['fealty']);
            });
        });

        describe('when game is private', function () {
            beforeEach(function () {
                this.game.gamePrivate = true;
            });

            it('should not include faction or agenda even when authenticated', function () {
                let summary = this.game.getSummary(undefined, true);
                let playerSummary = summary.players[this.player.username];

                expect(playerSummary.faction).toBeUndefined();
                expect(playerSummary.agendas).toEqual([undefined]);
            });
        });

        describe('when game has not started', function () {
            beforeEach(function () {
                this.game.started = false;
            });

            it('should not include faction or agenda even when authenticated', function () {
                let summary = this.game.getSummary(undefined, true);
                let playerSummary = summary.players[this.player.username];

                expect(playerSummary.faction).toBeUndefined();
                expect(playerSummary.agendas).toEqual([undefined]);
            });
        });
    });
});
