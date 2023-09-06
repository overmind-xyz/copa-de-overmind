/*
    This community built quest features a fantasy football platform where users can create their own 
    teams of football players to compete with other users. The platform will reward users based on 
    the performance of their teams at the end of each match-week. 

    Each team consists of 3 players and is represented by a non-fungible token (NFT).

    Match weeks: 
        The admin of the platform will submit a list of player names at the beginning of each week. 
        The list will contain the names of all players who will be playing in the upcoming week.
        There will be a minimum of 6 players in each list.
    
        Each match week has three sessions in it. 

            1. Team building open: 
                The match week starts with a team building open period. During this period, users
                can create their teams by choosing 3 players from the list of players submitted by
                the admin.

                This period lasts until the admin changes the game session. 

            2. Team building closed:
                The match week will be moved to this session when the admin changes the game 
                session. During this session, users cannot create new teams. This is to prevent 
                users from performing any teams with the knowledge of the results of the match week.

                This period lasts until the admin changes the game sessions, or when the match week 
                ends and the results are announced. 

            3. Teams ranked: 
                The final session of the match week. When ending the match week, the scores and 
                ranking for the teams are calculated. The scores are calculated based on the
                performance of the players in the team. The ranking is calculated based on the
                scores of the teams.

    Creating a team: 
        Users can create a team by choosing 3 players from the list of players available for that 
        match week. A new team NFT will be minted and transferred to the user. 

        A team can only be created during the team building open session.

        Users can create multiple teams and each team can be created multiple times. Note that in a 
        production environment, it is recommended to limit the number of teams a user can create by 
        requiring a fee to create a team. This fee could be use to pay out the platform admin as 
        well as contribute to the reward pool. 

    Team NFTs: 
        Team NFTs represent the ownership of fantasy teams created by the users. The team NFT 
        collection is an unlimited supply NFT collection that has no royalty. The collection's name
        is "TeamNFT Collection", the description is "Overmind Sport Fantasy TeamNFT Collection", and
        the URI is "ovm.team.collection". The NFT collection is to be created by the module's 
        resource account.

        Each team NFT has a unique name, and a constant description and URI. The name of each team 
        NFT will be in the format of "TeamNFT:{match_week}/{team_id}", where match_week is the
        id of the match week that the team is created in, and team_id is the id of the team. These 
        are both stored in the State resource. Both of these ID's start at 0. The description of 
        each team NFT is "Overmind Sport Fantasy TeamNFT", and the URI is "ovm.team".

        Each NFT has a TeamNFT resource which holds all of the information about the team.

    Changing the game session: 
        The admin can change the game session at any time. Only the admin can change the game 
        session. 

    Announcing the match week results: 
        The admin also can announce the results of the match week at any time. Only the admin can 
        announce the results of the match week. 

        When announcing the results, the admin will provide a list of goals and assists for each of 
        players that were available that match week. This data will be used to calculate the scores 
        and ranking for each team in the match week. 

        The 10 highest ranking teams will each be rewarded .02 APT. If there are less than 10 teams
        in the match week, then all teams will be rewarded.

        The session will also be changed to the "Teams ranked" sessions. 
    
    Scoring and Ranking: 
        The scoring of teams will be done by rewarding the following points based on the stats of 
        each player in the team: 
            - 6 points for each goal scored
            - 3 points for each assist made

        The score of a team is the sum of the points of all players in the team. 

        The ranking of teams will be done by sorting the teams by their scores. If two teams have 
        the same score, then the team with the lower team id (created earlier) will be ranked 
        higher. 1: the highest rank, 2: the second highest rank, and so on. 0 means not ranked. 

    Claiming rewards:
        Team owners can claim their rewards at any time after the results are announced. Only the
        owner of the team can claim the reward and this reward can only be claimed once. 

        The reward for each team in the top ten is .02 APT, and 0 for all other teams. 

        Note: team owners will be registered with the AptosCoin when they claim their rewards to 
        ensure they can receive the rewards.


*/
module overmind::sport_fantasy {
    //==============================================================================================
    // Dependencies
    //==============================================================================================
    use std::vector;
    use std::signer;
    use std::option;
    use std::string_utils;
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use aptos_token_objects::token;
    use std::string::{Self, String};
    use aptos_framework::object::{Self};
    use aptos_token_objects::collection;
    use aptos_std::simple_map::{Self, SimpleMap};
    use aptos_framework::aptos_coin::{AptosCoin};
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account::{Self, SignerCapability};

    #[test_only]
    use aptos_framework::aptos_coin::{Self};
    #[test_only]
    use aptos_token_objects::collection::{Collection};

    //==============================================================================================
    // Constants - DO NOT MODIFY
    //==============================================================================================

    // The seed use to create the module's resource account
    const SEED: vector<u8> = b"sport fantasy";
    
    //==============================================================================================
    // Error codes - DO NOT MODIFY
    //==============================================================================================
    const ECodeForAllErrors: u64 = 4586533;

    //==============================================================================================
    // Module Structs - DO NOT MODIFY
    //==============================================================================================

    /* 
        Holds information to be used in the module
    */
    struct State has key {
        // the signer cap of the module's resource account
        signer_cap: SignerCapability,
        // a list of players available for the current match week
        // Minimum of 6 players per match week
        // The default value is an empty vector. This will be replaced when create_match_week is 
        // called for the first time, and so one. 
        player_list: vector<Player>,
        // the id of the current match week
        // NOTE: the first match week has id 0 - meaning the first match week is the 0th match week 
        // and the first call of create_match_week does not increment the match week
        match_week: u8,
        // The current game session of the match week
        // 0: team building open, 1: team building closed, 2: teams ranked
        // default value is 1
        game_session: u8,
        // a list of simple map from team_id to nft_address of each match week
        // team id starts from 0
        team_id_to_nft_address_list: vector<SimpleMap<u64, address>>,
        // a flag to indicate if the result is announced of each match week
        is_result_announced: vector<bool>,
        // an event to be emitted
        event_handlers: EventHandlers
    } 

    /*
        Holds data about a football player
    */
    struct Player has key, store, drop {
        // id of the player
        id: u64,
        // name of the player
        name: vector<u8>
    }

    /*
        Holds data about a user team
    */
    struct TeamNFT has key, store {
        // id of the team
        id: u64,
        // creator of the team
        creator: address,
        // id of the first player
        player1_id: u64,
        // id of the second player
        player2_id: u64,
        // id of the third player
        player3_id: u64,
        // points of the team
        // 0: default value
        points: u64,
        // rank of the team
        // 0: not ranked, 1: the highest rank, 2: the second highest rank, and so on
        rank: u64,
        // a flag to indicate if the reward has been claimed
        is_reward_claimed: bool,
    }

    /*
        Holds data about event handlers
    */
    struct EventHandlers has store {
        // event handler for CreateTeamNFTEvent
        create_team_events: EventHandle<CreateTeamNFTEvent>,
        // event handler for AnnounceResultEvent
        announce_result_events: EventHandle<AnnounceResultEvent>,
        // event handler for ClaimRewardEvent
        claim_reward_events: EventHandle<ClaimRewardEvent>,
        // event handler for ChangeGameSessionEvent
        change_game_session_events: EventHandle<ChangeGameSessionEvent>
    }
    
    //==============================================================================================
    // Event structs - DO NOT MODIFY
    //==============================================================================================

    /* 
        Event to be emitted when the team is created
    */
    struct CreateTeamNFTEvent has store, drop {
        // id of the current match week
        match_week: u8,
        // creator of the team
        creator: address,
        // id of the team
        team: u64,
        // id of the first player
        player1_id: u64,
        // id of the second player
        player2_id: u64,
        // id of the third player
        player3_id: u64,
        // timestamp of the event 
        event_creation_timestamp_seconds: u64
    }

    /*
        Event to be emitted when the results of the match week are announced
    */
    struct AnnounceResultEvent has store, drop {
        // id of the match week
        match_week: u8,
        // a list of goals scored by players, ordered by player id
        player_goals: vector<u64>,
        // a list of assists made by players, ordered by player id
        player_assists: vector<u64>,
        // an amount of teams in the match week
        team_count: u64,
        // timestamp of the event
        event_creation_timestamp_seconds: u64
    }

    /*
        Event to be emitted when the reward is claimed (not to be emitted when the reward is 0)
    */
    struct ClaimRewardEvent has store, drop {
        // id of the match week
        match_week: u8,
        // owner of the team
        owner: address,
        // id of the team
        team: u64,
        // reward amount
        reward: u64,
        // timestamp of the event
        event_creation_timestamp_seconds: u64
    }

    /*
        Event to be emitted when the game session is changed
    */
    struct ChangeGameSessionEvent has store, drop {
        // id of the match week
        match_week: u8,
        // old session
        old_session: u8,
        // new session
        new_session: u8,
        // timestamp of the event
        event_creation_timestamp_seconds: u64
    }

    //==============================================================================================
    // Functions
    //==============================================================================================

    /* 
        Initialize the module by creating the module's resource account, registering the resource 
        account with the AptosCoin, creating the team NFT collection, and creating and moving the 
        State resource to the resource account.
        @param account - signer of the admin account
    */
    fun init_module(account: &signer) {
        
    }

    /*
        Create a new fantasy team for the account with the given players and updates the State 
        resource. Aborts if there are any duplicated players, any players do not exist, or team 
        building is not open.
        @param account - account to create and receive the team NFT
        @param player1_id - id of the first player
        @param player2_id - id of the second player
        @param player3_id - id of the third player
    */
    public entry fun create_team(
        account: &signer,
        player1_id: u64,
        player2_id: u64,
        player3_id: u64,
    ) acquires State {

    }

    /*
        Allows the admin to change the game session. Aborts if the caller is not the admin. 
        @param admin - admin
    */
    public entry fun change_game_session(
        admin: &signer,
        new_session: u8,
    ) acquires State {
        
    }

    /*
        Announce the stats of the current match week and calculate the scores and ranking for each 
        team in the match week. Updates the State resource. Aborts if the caller is not the admin, 
        the result has already been announced, or if the resource account does not have enough 
        AptosCoin to reward the teams.
        @param admin - admin, who announces the result
        @param player_goals - a list of goals scored by each player ordered by player id
        @param player_assists - a list of assists made by each player ordered by player id
    */
    public entry fun announce_with_stats(
        admin: &signer,
        player_goals: vector<u64>,
        player_assists: vector<u64>
    ) acquires State, TeamNFT {
        
    }

    /*
        Increments the match week and replaces the player list with the given list. Updates the 
        State resource as needed. Aborts if the caller is not the admin, or the player list is less 
        than 6.
        @param admin: the admin, who can call this function
        @param player_name_list: a list of player names for the new match week
    */
    public entry fun create_match_week(
        admin: &signer,
        player_name_list: vector<vector<u8>>,
    ) acquires State {
        
    }

    /*
        Allows the owner of a team NFT to claim their rewards. Aborts if the match week is invalid, 
        the team id is invalid, the caller is not the owner of the team, the results for the match 
        week have not been announced, or the reward has already been claimed for this team. 
        @param account - the account that claims the reward
        @param match_week - the match week id that the team is in
        @param team_id - the team id that the account wants to claim the reward
    */
    public entry fun claim_reward(
        account: &signer,
        match_week: u8,
        team_id: u64,
    ) acquires State, TeamNFT {

    }

    //==============================================================================================
    // Helper functions
    //==============================================================================================

    //==============================================================================================
    // Validation functions
    //==============================================================================================

    //==============================================================================================
    // Tests - DO NOT MODIFY
    //==============================================================================================

    #[test]
    fun test_init_module_success() acquires State {
        let admin = account::create_account_for_test(@overmind);
        init_module(&admin);

        let resource_account_address = account::create_resource_address(&@overmind, b"sport fantasy");
        let state = borrow_global<State>(resource_account_address);

        assert!(&state.signer_cap == &account::create_test_signer_cap(resource_account_address), 10);

        let expected_team_nft_collection_address = collection::create_collection_address(
            &resource_account_address,
            &string::utf8(b"TeamNFT Collection")
        );
        assert!(object::is_object(expected_team_nft_collection_address) == true, 0);
        let team_nft_collection = object::address_to_object<Collection>(expected_team_nft_collection_address);
        assert!(object::owner<Collection>(team_nft_collection) == resource_account_address, 0);
        assert!(
            collection::creator<Collection>(team_nft_collection) == resource_account_address, 
            0
        );
        assert!(
            option::is_some<u64>(&collection::count<Collection>(team_nft_collection)) == true, 
            0
        );
        assert!(
            option::contains<u64>(&collection::count<Collection>(team_nft_collection), &0) == true, 
            0
        );
        assert!(
            collection::description<Collection>(team_nft_collection) == string::utf8(b"Overmind Sport Fantasy TeamNFT Collection"), 
            0
        );
        assert!(
            collection::name<Collection>(team_nft_collection) == string::utf8(b"TeamNFT Collection"), 
            0
        );
        assert!(
            collection::uri<Collection>(team_nft_collection) == string::utf8(b"ovm.team.collection"), 
            0
        );

        assert!(event::counter(&state.event_handlers.create_team_events) == 0, 6);
        assert!(event::counter(&state.event_handlers.announce_result_events) == 0, 6);
        assert!(event::counter(&state.event_handlers.claim_reward_events) == 0, 6);
        assert!(event::counter(&state.event_handlers.change_game_session_events) == 0, 6);
    }

    #[test]
    fun test_create_team_success() acquires State, TeamNFT {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let admin = account::create_account_for_test(@overmind);
        init_module(&admin);

        let player_name_list = vector[
            b"Tony",
            b"Adam",
            b"Dan",
            b"TC",
            b"John",
            b"Rath",
        ];
        create_match_week(&admin, player_name_list);

        change_game_session(&admin, 0);

        let account = account::create_account_for_test(@0xCAFE);
        let player1_id = 0;
        let player2_id = 1;
        let player3_id = 2;
        create_team(&account, player1_id, player2_id, player3_id);

        let resource_account_address = account::create_resource_address(&@overmind, b"sport fantasy");
        let state = borrow_global<State>(resource_account_address);
        let team_id_to_nft_address_list = state.team_id_to_nft_address_list;
        let team_id_to_nft_address = vector::borrow(&team_id_to_nft_address_list, 0);
        let team_count = simple_map::length<u64, address>(team_id_to_nft_address);
        assert!(team_count == 1, 0);
        let team_address_0 = *simple_map::borrow<u64, address>(team_id_to_nft_address, &0);
        let team_0 = borrow_global<TeamNFT>(move team_address_0);
        assert!(team_0.id == 0, 1);
        assert!(team_0.player1_id == 0, 2);
        assert!(team_0.player2_id == 1, 3);
        assert!(team_0.player3_id == 2, 4);
        assert!(team_0.creator == signer::address_of(&account), 5);
        assert!(team_0.rank == 0, 6);
        assert!(team_0.points == 0, 7);
        assert!(team_0.is_reward_claimed == false, 8);

        let expected_token_address = token::create_token_address(
            &resource_account_address, 
            &string::utf8(b"TeamNFT Collection"),
            &string::utf8(b"TeamNFT:0/0")
        );
        assert!(
            object::is_object(expected_token_address) == true, 
            0
        );
        let team_token = object::address_to_object<TeamNFT>(expected_token_address);
        assert!(
            object::owner<TeamNFT>(team_token) == signer::address_of(&account), 
            0
        );
        assert!(
            token::creator<TeamNFT>(team_token) == resource_account_address, 
            0
        );
        assert!(
            token::collection_name<TeamNFT>(team_token) == string::utf8(b"TeamNFT Collection"), 
            0
        );
        let description = string::utf8( b"Overmind Sport Fantasy TeamNFT");
        assert!(
            token::description<TeamNFT>(team_token) == description, 
            0
        );
        assert!(
            token::name<TeamNFT>(team_token) == string::utf8(b"TeamNFT:0/0"), 
            0
        );
        assert!(
            token::uri<TeamNFT>(team_token) == string::utf8(b"ovm.team"), 
            0
        );
        assert!(
            option::is_none(&token::royalty<TeamNFT>(team_token)) == true, 
            0
        );

        assert!(event::counter(&state.event_handlers.create_team_events) == 1, 6);
        assert!(event::counter(&state.event_handlers.announce_result_events) == 0, 6);
        assert!(event::counter(&state.event_handlers.claim_reward_events) == 0, 6);
        assert!(event::counter(&state.event_handlers.change_game_session_events) == 1, 6);
    }

    #[test]
    #[expected_failure(abort_code = ECodeForAllErrors, location = Self)]
    fun test_create_team_failure_player_not_exist_1() acquires State {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let admin = account::create_account_for_test(@overmind);
        init_module(&admin);

        let player_name_list = vector[
            b"Tony",
            b"Adam",
            b"Dan",
            b"TC",
            b"John",
            b"Rath",
        ];
        create_match_week(&admin, player_name_list);

        change_game_session(&admin, 0);

        let account = account::create_account_for_test(@0xCAFE);
        let player1_id = 0;
        let player2_id = 1;
        let player3_id = 9;
        create_team(&account, player1_id, player2_id, player3_id);
    }

    #[test]
    #[expected_failure(abort_code = ECodeForAllErrors, location = Self)]
    fun test_create_team_failure_player_not_exist_2() acquires State {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let admin = account::create_account_for_test(@overmind);
        init_module(&admin);

        let player_name_list = vector[
            b"Tony",
            b"Adam",
            b"Dan",
            b"TC",
            b"John",
            b"Rath",
        ];
        create_match_week(&admin, player_name_list);

        change_game_session(&admin, 0);

        let account = account::create_account_for_test(@0xCAFE);
        let player1_id = 0;
        let player3_id = 1;
        let player2_id = 9;
        create_team(&account, player1_id, player2_id, player3_id);
    }

    #[test]
    #[expected_failure(abort_code = ECodeForAllErrors, location = Self)]
    fun test_create_team_failure_player_not_exist_3() acquires State {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let admin = account::create_account_for_test(@overmind);
        init_module(&admin);

        let player_name_list = vector[
            b"Tony",
            b"Adam",
            b"Dan",
            b"TC",
            b"John",
            b"Rath",
        ];
        create_match_week(&admin, player_name_list);

        change_game_session(&admin, 0);

        let account = account::create_account_for_test(@0xCAFE);
        let player3_id = 0;
        let player2_id = 1;
        let player1_id = 9;
        create_team(&account, player1_id, player2_id, player3_id);
    }

    #[test]
    #[expected_failure(abort_code = ECodeForAllErrors, location = Self)]
    fun test_create_team_failure_players_duplicated() acquires State {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let admin = account::create_account_for_test(@overmind);
        init_module(&admin);

        let player_name_list = vector[
            b"Tony",
            b"Adam",
            b"Dan",
            b"TC",
            b"John",
            b"Rath",
        ];
        create_match_week(&admin, player_name_list);

        change_game_session(&admin, 0);

        let account = account::create_account_for_test(@0xCAFE);
        let player1_id = 0;
        let player2_id = 1;
        let player3_id = 1;
        create_team(&account, player1_id, player2_id, player3_id);
    }

    #[test]
    #[expected_failure(abort_code = ECodeForAllErrors, location = Self)]
    fun test_create_team_failure_session_closed() acquires State {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let admin = account::create_account_for_test(@overmind);
        init_module(&admin);

         let player_name_list = vector[
            b"Tony",
            b"Adam",
            b"Dan",
            b"TC",
            b"John",
            b"Rath",
        ];
        create_match_week(&admin, player_name_list);

        let account = account::create_account_for_test(@0xCAFE);
        let player1_id = 0;
        let player2_id = 1;
        let player3_id = 2;
        create_team(&account, player1_id, player2_id, player3_id);
    }

    #[test]
    fun test_create_teams_success() acquires State, TeamNFT {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let admin = account::create_account_for_test(@overmind);
        init_module(&admin);

        let player_name_list = vector[
            b"Tony",
            b"Adam",
            b"Dan",
            b"TC",
            b"John",
            b"Rath",
        ];
        create_match_week(&admin, player_name_list);

        change_game_session(&admin, 0);

        let account_0 = account::create_account_for_test(@0xCAFE);
        let player1_id = 0;
        let player2_id = 1;
        let player3_id = 2;
        create_team(&account_0, player1_id, player2_id, player3_id);
        let account_1 = account::create_account_for_test(@0xDAD);
        let player1_id = 0;
        let player2_id = 2;
        let player3_id = 3;
        create_team(&account_1, player1_id, player2_id, player3_id);
        let account_2 = account::create_account_for_test(@0xC0FFEE);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account_2, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account_2, player1_id, player2_id, player3_id);

        let resource_account_address = account::create_resource_address(&@overmind, b"sport fantasy");
        let state = borrow_global<State>(resource_account_address);
        let team_id_to_nft_address_list = state.team_id_to_nft_address_list;
        let team_id_to_nft_address = vector::borrow(&team_id_to_nft_address_list, 0);
        let team_count = simple_map::length<u64, address>(team_id_to_nft_address);
        assert!(team_count == 4, 0);
        let team_address_0 = *simple_map::borrow<u64, address>(team_id_to_nft_address, &0);
        let team_0 = borrow_global<TeamNFT>(team_address_0);
        assert!(team_0.id == 0, 1);
        assert!(team_0.player1_id == 0, 2);
        assert!(team_0.player2_id == 1, 3);
        assert!(team_0.player3_id == 2, 4);
        let team_address_1 = *simple_map::borrow<u64, address>(team_id_to_nft_address, &1);
        let team_1 = borrow_global<TeamNFT>(team_address_1);
        assert!(team_1.id == 1, 5);
        assert!(team_1.player1_id == 0, 6);
        assert!(team_1.player2_id == 2, 7);
        assert!(team_1.player3_id == 3, 8);
        let team_address_2 = *simple_map::borrow<u64, address>(team_id_to_nft_address, &2);
        let team_2 = borrow_global<TeamNFT>(team_address_2);
        assert!(team_2.id == 2, 9);
        assert!(team_2.player1_id == 3, 10);
        assert!(team_2.player2_id == 4, 11);
        assert!(team_2.player3_id == 5, 12);
        let team_address_3 = *simple_map::borrow<u64, address>(team_id_to_nft_address, &3);
        let team_3 = borrow_global<TeamNFT>(team_address_3);
        assert!(team_3.id == 3, 13);
        assert!(team_3.player1_id == 3, 14);
        assert!(team_3.player2_id == 4, 15);
        assert!(team_3.player3_id == 5, 16);

        assert!(
            object::is_object(team_address_0) == true, 
            0
        );
        let team_token = object::address_to_object<TeamNFT>(team_address_0);
        assert!(
            object::owner<TeamNFT>(team_token) == signer::address_of(&account_0), 
            0
        );
        assert!(
            token::creator<TeamNFT>(team_token) == resource_account_address, 
            0
        );
        assert!(
            token::collection_name<TeamNFT>(team_token) == string::utf8(b"TeamNFT Collection"), 
            0
        );
        let description = string::utf8( b"Overmind Sport Fantasy TeamNFT");
        assert!(
            token::description<TeamNFT>(team_token) == description, 
            0
        );
        assert!(
            token::name<TeamNFT>(team_token) == string::utf8(b"TeamNFT:0/0"), 
            0
        );
        assert!(
            token::uri<TeamNFT>(team_token) == string::utf8(b"ovm.team"), 
            0
        );
        assert!(
            option::is_none(&token::royalty<TeamNFT>(team_token)) == true, 
            0
        );

        assert!(
            object::is_object(team_address_1) == true, 
            0
        );
        let team_token = object::address_to_object<TeamNFT>(team_address_1);
        assert!(
            object::owner<TeamNFT>(team_token) == signer::address_of(&account_1), 
            0
        );
        assert!(
            token::creator<TeamNFT>(team_token) == resource_account_address, 
            0
        );
        assert!(
            token::collection_name<TeamNFT>(team_token) == string::utf8(b"TeamNFT Collection"), 
            0
        );
        let description = string::utf8( b"Overmind Sport Fantasy TeamNFT");
        assert!(
            token::description<TeamNFT>(team_token) == description, 
            0
        );
        assert!(
            token::name<TeamNFT>(team_token) == string::utf8(b"TeamNFT:0/1"), 
            0
        );
        assert!(
            token::uri<TeamNFT>(team_token) == string::utf8(b"ovm.team"), 
            0
        );
        assert!(
            option::is_none(&token::royalty<TeamNFT>(team_token)) == true, 
            0
        );

        assert!(
            object::is_object(team_address_2) == true, 
            0
        );
        let team_token = object::address_to_object<TeamNFT>(team_address_2);
        assert!(
            object::owner<TeamNFT>(team_token) == signer::address_of(&account_2), 
            0
        );
        assert!(
            token::creator<TeamNFT>(team_token) == resource_account_address, 
            0
        );
        assert!(
            token::collection_name<TeamNFT>(team_token) == string::utf8(b"TeamNFT Collection"), 
            0
        );
        let description = string::utf8( b"Overmind Sport Fantasy TeamNFT");
        assert!(
            token::description<TeamNFT>(team_token) == description, 
            0
        );
        assert!(
            token::name<TeamNFT>(team_token) == string::utf8(b"TeamNFT:0/2"), 
            0
        );
        assert!(
            token::uri<TeamNFT>(team_token) == string::utf8(b"ovm.team"), 
            0
        );
        assert!(
            option::is_none(&token::royalty<TeamNFT>(team_token)) == true, 
            0
        );

        assert!(
            object::is_object(team_address_3) == true, 
            0
        );
        let team_token = object::address_to_object<TeamNFT>(team_address_3);
        assert!(
            object::owner<TeamNFT>(team_token) == signer::address_of(&account_2), 
            0
        );
        assert!(
            token::creator<TeamNFT>(team_token) == resource_account_address, 
            0
        );
        assert!(
            token::collection_name<TeamNFT>(team_token) == string::utf8(b"TeamNFT Collection"), 
            0
        );
        let description = string::utf8( b"Overmind Sport Fantasy TeamNFT");
        assert!(
            token::description<TeamNFT>(team_token) == description, 
            0
        );
        assert!(
            token::name<TeamNFT>(team_token) == string::utf8(b"TeamNFT:0/3"), 
            0
        );
        assert!(
            token::uri<TeamNFT>(team_token) == string::utf8(b"ovm.team"), 
            0
        );
        assert!(
            option::is_none(&token::royalty<TeamNFT>(team_token)) == true, 
            0
        );

        assert!(event::counter(&state.event_handlers.create_team_events) == 4, 6);
        assert!(event::counter(&state.event_handlers.announce_result_events) == 0, 6);
        assert!(event::counter(&state.event_handlers.claim_reward_events) == 0, 6);
        assert!(event::counter(&state.event_handlers.change_game_session_events) == 1, 6);
    }

    #[test]
    #[expected_failure(abort_code = ECodeForAllErrors, location = Self)]
    fun test_create_teams_failure_session_closed() acquires State {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let admin = account::create_account_for_test(@overmind);
        init_module(&admin);

        let player_name_list = vector[
            b"Tony",
            b"Adam",
            b"Dan",
            b"TC",
            b"John",
            b"Rath",
        ];
        create_match_week(&admin, player_name_list);

        change_game_session(&admin, 0);

        let account = account::create_account_for_test(@0xCAFE);
        let player1_id = 0;
        let player2_id = 1;
        let player3_id = 2;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xDAD);
        let player1_id = 0;
        let player2_id = 2;
        let player3_id = 3;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xC0FFEE);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);

        change_game_session(&admin, 1);

        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
    }

    #[test]
    fun test_announce_success() acquires State, TeamNFT {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let admin = account::create_account_for_test(@overmind);
        init_module(&admin);

        let player_name_list = vector[
            b"Tony",
            b"Adam",
            b"Dan",
            b"TC",
            b"John",
            b"Rath",
        ];
        create_match_week(&admin, player_name_list);

        change_game_session(&admin, 0);

        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&aptos_framework);
        let resource_account_address = account::create_resource_address(&@overmind, b"sport fantasy");
        aptos_coin::mint(&aptos_framework, resource_account_address, 4 * 2000000);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let account = account::create_account_for_test(@0xCAFE);
        let player1_id = 0;
        let player2_id = 1;
        let player3_id = 2;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xDAD);
        let player1_id = 0;
        let player2_id = 2;
        let player3_id = 3;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xC0FFEE);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);

        let player_goals = vector[
            0,
            1,
            1,
            0,
            0,
            1,
        ];
        let player_assists = vector[
            1,
            1,
            0,
            0,
            1,
            1,
        ];
        announce_with_stats(&admin, player_goals, player_assists);

        let resource_account_address = account::create_resource_address(&@overmind, b"sport fantasy");
        let state = borrow_global<State>(resource_account_address);
        let team_id_to_nft_address_list = state.team_id_to_nft_address_list;
        let team_id_to_nft_address = vector::borrow(&team_id_to_nft_address_list, 0);
        let team_count = simple_map::length<u64, address>(team_id_to_nft_address);
        assert!(team_count == 4, 0);
        let team_address_0 = *simple_map::borrow<u64, address>(team_id_to_nft_address, &0);
        let team_0 = borrow_global<TeamNFT>(move team_address_0);
        assert!(team_0.points == 18, 1);
        assert!(team_0.rank == 1, 2);
        let team_address_1 = *simple_map::borrow<u64, address>(team_id_to_nft_address, &1);
        let team_1 = borrow_global<TeamNFT>(move team_address_1);
        assert!(team_1.points == 9, 3);
        assert!(team_1.rank == 4, 4);
        let team_address_2 = *simple_map::borrow<u64, address>(team_id_to_nft_address, &2);
        let team_2 = borrow_global<TeamNFT>(move team_address_2);
        assert!(team_2.points == 12, 5);
        assert!(team_2.rank == 2, 6);
        let team_address_3 = *simple_map::borrow<u64, address>(team_id_to_nft_address, &3);
        let team_3 = borrow_global<TeamNFT>(move team_address_3);
        assert!(team_3.points == 12, 7);
        assert!(team_3.rank == 3, 8);

        assert!(
            state.game_session == 2, 
            18
        );
        
        assert!(event::counter(&state.event_handlers.claim_reward_events) == 0, 6);
        assert!(event::counter(&state.event_handlers.change_game_session_events) == 2, 6);
        assert!(event::counter(&state.event_handlers.create_team_events) == 4, 9);
        assert!(event::counter(&state.event_handlers.announce_result_events) == 1, 10);
    }

    #[test]
    #[expected_failure(abort_code = ECodeForAllErrors, location = Self)]
    fun test_announce_failure_not_admin() acquires State, TeamNFT {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let admin = account::create_account_for_test(@overmind);
        init_module(&admin);

        let player_name_list = vector[
            b"Tony",
            b"Adam",
            b"Dan",
            b"TC",
            b"John",
            b"Rath",
        ];
        create_match_week(&admin, player_name_list);

        change_game_session(&admin, 0);

        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&aptos_framework);
        let resource_account_address = account::create_resource_address(&@overmind, b"sport fantasy");
        aptos_coin::mint(&aptos_framework, resource_account_address, 4 * 2000000);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let account = account::create_account_for_test(@0xCAFE);
        let player1_id = 0;
        let player2_id = 1;
        let player3_id = 2;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xDAD);
        let player1_id = 0;
        let player2_id = 2;
        let player3_id = 3;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xC0FFEE);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);

        let player_goals = vector[
            0,
            1,
            1,
            0,
            0,
            1,
        ];
        let player_assists = vector[
            1,
            1,
            0,
            0,
            1,
            1,
        ];
        announce_with_stats(&account, player_goals, player_assists);
    }

    #[test]
    #[expected_failure(abort_code = ECodeForAllErrors, location = Self)]
    fun test_announce_failure_admin_has_too_less_apt() acquires State, TeamNFT {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let admin = account::create_account_for_test(@overmind);
        init_module(&admin);

        let player_name_list = vector[
            b"Tony",
            b"Adam",
            b"Dan",
            b"TC",
            b"John",
            b"Rath",
        ];
        create_match_week(&admin, player_name_list);

        change_game_session(&admin, 0);

        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&aptos_framework);
        let resource_account_address = account::create_resource_address(&@overmind, b"sport fantasy");
        aptos_coin::mint(&aptos_framework, resource_account_address, 3 * 2000000);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let account = account::create_account_for_test(@0xCAFE);
        let player1_id = 0;
        let player2_id = 1;
        let player3_id = 2;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xDAD);
        let player1_id = 0;
        let player2_id = 2;
        let player3_id = 3;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xC0FFEE);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);

        let player_goals = vector[
            0,
            1,
            1,
            0,
            0,
            1,
        ];
        let player_assists = vector[
            1,
            1,
            0,
            0,
            1,
            1,
        ];
        announce_with_stats(&admin, player_goals, player_assists);

    }

    #[test]
    fun test_create_team_after_announced_success() acquires State, TeamNFT {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let admin = account::create_account_for_test(@overmind);
        init_module(&admin);

        let player_name_list = vector[
            b"Tony",
            b"Adam",
            b"Dan",
            b"TC",
            b"John",
            b"Rath",
        ];
        create_match_week(&admin, player_name_list);

        change_game_session(&admin, 0);

        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&aptos_framework);
        let resource_account_address = account::create_resource_address(&@overmind, b"sport fantasy");
        aptos_coin::mint(&aptos_framework, resource_account_address, 4 * 2000000);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let account = account::create_account_for_test(@0xCAFE);
        let player1_id = 0;
        let player2_id = 1;
        let player3_id = 2;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xDAD);
        let player1_id = 0;
        let player2_id = 2;
        let player3_id = 3;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xC0FFEE);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);

        let player_goals = vector[
            0,
            1,
            1,
            0,
            0,
            1,
        ];
        let player_assists = vector[
            1,
            1,
            0,
            0,
            1,
            1,
        ];
        announce_with_stats(&admin, player_goals, player_assists);

        let player_name_list = vector[
            b"John",
            b"Paul",
            b"George",
            b"Ringo",
            b"Beatles",
            b"Liverpool",
        ];
        create_match_week(&admin, player_name_list);

        change_game_session(&admin, 0);

        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);

        let resource_account = account::create_resource_address(&@overmind, b"sport fantasy");
        let state = borrow_global<State>(resource_account);
        assert!(event::counter(&state.event_handlers.create_team_events) == 5, 6);
        assert!(event::counter(&state.event_handlers.announce_result_events) == 1, 6);
        assert!(event::counter(&state.event_handlers.claim_reward_events) == 0, 6);
        assert!(event::counter(&state.event_handlers.change_game_session_events) == 3, 6);
    }

    #[test]
    #[expected_failure(abort_code = ECodeForAllErrors, location = Self)]
    fun test_create_team_after_announced_failure_session_not_open() acquires State, TeamNFT {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let admin = account::create_account_for_test(@overmind);
        init_module(&admin);

        let player_name_list = vector[
            b"Tony",
            b"Adam",
            b"Dan",
            b"TC",
            b"John",
            b"Rath",
        ];
        create_match_week(&admin, player_name_list);

        change_game_session(&admin, 0);

        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&aptos_framework);
        let resource_account_address = account::create_resource_address(&@overmind, b"sport fantasy");
        aptos_coin::mint(&aptos_framework, resource_account_address, 4 * 2000000);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let account = account::create_account_for_test(@0xCAFE);
        let player1_id = 0;
        let player2_id = 1;
        let player3_id = 2;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xDAD);
        let player1_id = 0;
        let player2_id = 2;
        let player3_id = 3;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xC0FFEE);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);

        let player_goals = vector[
            0,
            1,
            1,
            0,
            0,
            1,
        ];
        let player_assists = vector[
            1,
            1,
            0,
            0,
            1,
            1,
        ];
        announce_with_stats(&admin, player_goals, player_assists);

        let player_name_list = vector[
            b"John",
            b"Paul",
            b"George",
            b"Ringo",
            b"Beatles",
            b"Liverpool",
        ];
        create_match_week(&admin, player_name_list);

        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
    }

    #[test]
    fun test_announce_no_team_success() acquires State, TeamNFT {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let admin = account::create_account_for_test(@overmind);
        init_module(&admin);

        let player_name_list = vector[
            b"Tony",
            b"Adam",
            b"Dan",
            b"TC",
            b"John",
            b"Rath",
        ];
        create_match_week(&admin, player_name_list);

        change_game_session(&admin, 0);

        let player_goals = vector[
            0,
            1,
            1,
            0,
            0,
            1,
        ];
        let player_assists = vector[
            1,
            1,
            0,
            0,
            1,
            1,
        ];
        announce_with_stats(&admin, player_goals, player_assists);

        let resource_account = account::create_resource_address(&@overmind, b"sport fantasy");
        let state = borrow_global<State>(resource_account);
        assert!(event::counter(&state.event_handlers.create_team_events) == 0, 6);
        assert!(event::counter(&state.event_handlers.announce_result_events) == 1, 6);
        assert!(event::counter(&state.event_handlers.claim_reward_events) == 0, 6);
        assert!(event::counter(&state.event_handlers.change_game_session_events) == 2, 6);
    }

    #[test]
    #[expected_failure(abort_code = ECodeForAllErrors, location = Self)]
    fun test_announce_failure_double_announce() acquires State, TeamNFT {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let admin = account::create_account_for_test(@overmind);
        init_module(&admin);

        let player_name_list = vector[
            b"Tony",
            b"Adam",
            b"Dan",
            b"TC",
            b"John",
            b"Rath",
        ];
        create_match_week(&admin, player_name_list);

        change_game_session(&admin, 0);

        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&aptos_framework);
        let resource_account_address = account::create_resource_address(&@overmind, b"sport fantasy");
        aptos_coin::mint(&aptos_framework, resource_account_address, 0 * 2000000);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let player_goals = vector[
            0,
            1,
            1,
            0,
            0,
            1,
        ];
        let player_assists = vector[
            1,
            1,
            0,
            0,
            1,
            1,
        ];
        announce_with_stats(&admin, player_goals, player_assists);
        announce_with_stats(&admin, player_goals, player_assists);
    }

    #[test]
    fun test_claimed_top10_success() acquires State, TeamNFT {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let admin = account::create_account_for_test(@overmind);
        init_module(&admin);

        let player_name_list = vector[
            b"Tony",
            b"Adam",
            b"Dan",
            b"TC",
            b"John",
            b"Rath",
        ];
        create_match_week(&admin, player_name_list);

        change_game_session(&admin, 0);

        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&aptos_framework);
        let resource_account_address = account::create_resource_address(&@overmind, b"sport fantasy");
        aptos_coin::mint(&aptos_framework, resource_account_address, 4 * 2000000);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let account = account::create_account_for_test(@0xCAFE);
        let player1_id = 0;
        let player2_id = 1;
        let player3_id = 2;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xDAD);
        let player1_id = 0;
        let player2_id = 2;
        let player3_id = 3;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xC0FFEE);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);

        let player_goals = vector[
            0,
            1,
            1,
            0,
            0,
            1,
        ];
        let player_assists = vector[
            1,
            1,
            0,
            0,
            1,
            1,
        ];

        announce_with_stats(&admin, player_goals, player_assists);

        claim_reward(&account, 0, 3);
        assert!(coin::balance<AptosCoin>(signer::address_of(&account)) == 2000000, 0);
        let resource_account = account::create_resource_address(&@overmind, b"sport fantasy");
        let state = borrow_global<State>(resource_account);
        assert!(event::counter(&state.event_handlers.create_team_events) == 4, 6);
        assert!(event::counter(&state.event_handlers.announce_result_events) == 1, 6);
        assert!(event::counter(&state.event_handlers.claim_reward_events) == 1, 6);
        assert!(event::counter(&state.event_handlers.change_game_session_events) == 2, 6);
    }

    #[test]
    #[expected_failure(abort_code = ECodeForAllErrors, location = Self)]
    fun test_claimed_failure_double_claim() acquires State, TeamNFT {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let admin = account::create_account_for_test(@overmind);
        init_module(&admin);

        let player_name_list = vector[
            b"Tony",
            b"Adam",
            b"Dan",
            b"TC",
            b"John",
            b"Rath",
        ];
        create_match_week(&admin, player_name_list);

        change_game_session(&admin, 0);

        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&aptos_framework);
        let resource_account_address = account::create_resource_address(&@overmind, b"sport fantasy");
        aptos_coin::mint(&aptos_framework, resource_account_address, 4 * 2000000);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let account = account::create_account_for_test(@0xCAFE);
        let player1_id = 0;
        let player2_id = 1;
        let player3_id = 2;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xDAD);
        let player1_id = 0;
        let player2_id = 2;
        let player3_id = 3;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xC0FFEE);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);

        let player_goals = vector[
            0,
            1,
            1,
            0,
            0,
            1,
        ];
        let player_assists = vector[
            1,
            1,
            0,
            0,
            1,
            1,
        ];

        announce_with_stats(&admin, player_goals, player_assists);

        claim_reward(&account, 0, 3);
        claim_reward(&account, 0, 3);
    }

    #[test]
    fun test_claimed_not_in_top10_success() acquires State, TeamNFT {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let admin = account::create_account_for_test(@overmind);
        init_module(&admin);

        let player_name_list = vector[
            b"Tony",
            b"Adam",
            b"Dan",
            b"TC",
            b"John",
            b"Rath",
        ];
        create_match_week(&admin, player_name_list);

        change_game_session(&admin, 0);

        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&aptos_framework);
        let resource_account_address = account::create_resource_address(&@overmind, b"sport fantasy");
        aptos_coin::mint(&aptos_framework, resource_account_address, 10 * 2000000);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let account = account::create_account_for_test(@0xCAFE);
        let player1_id = 0;
        let player2_id = 1;
        let player3_id = 2;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xDAD);
        let player1_id = 0;
        let player2_id = 2;
        let player3_id = 3;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xC0FFEE);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);

        let not_win_account = account::create_account_for_test(@0xDEADBEEF);
        let player1_id = 0;
        let player2_id = 3;
        let player3_id = 4;
        create_team(&not_win_account, player1_id, player2_id, player3_id);

        let player_goals = vector[
            0,
            1,
            1,
            0,
            0,
            1,
        ];
        let player_assists = vector[
            1,
            1,
            0,
            0,
            1,
            1,
        ];

        announce_with_stats(&admin, player_goals, player_assists);

        claim_reward(&not_win_account, 0,10);
        let not_win_account_balance = 0;
        if (coin::is_account_registered<AptosCoin>(signer::address_of(&not_win_account))) {
            not_win_account_balance = coin::balance<AptosCoin>(signer::address_of(&not_win_account));
        };
        assert!(not_win_account_balance == 0, 0);
        let resource_account = account::create_resource_address(&@overmind, b"sport fantasy");
        let state = borrow_global<State>(resource_account);
        assert!(event::counter(&state.event_handlers.create_team_events) == 11, 6);
        assert!(event::counter(&state.event_handlers.announce_result_events) == 1, 6);
        assert!(event::counter(&state.event_handlers.claim_reward_events) == 0, 6);
        assert!(event::counter(&state.event_handlers.change_game_session_events) == 2, 6);
    }

    #[test]
    #[expected_failure(abort_code = ECodeForAllErrors, location = Self)]
    fun test_claimed_failure_it_is_before_result_announced() acquires State, TeamNFT {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let admin = account::create_account_for_test(@overmind);
        init_module(&admin);

        let player_name_list = vector[
            b"Tony",
            b"Adam",
            b"Dan",
            b"TC",
            b"John",
            b"Rath",
        ];
        create_match_week(&admin, player_name_list);

        change_game_session(&admin, 0);

        let account = account::create_account_for_test(@0xCAFE);
        let player1_id = 0;
        let player2_id = 1;
        let player3_id = 2;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xDAD);
        let player1_id = 0;
        let player2_id = 2;
        let player3_id = 3;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xC0FFEE);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);

        claim_reward(&account, 0, 3);
    }

    #[test]
    fun test_create_team_and_announce_three_matchweeks_success() acquires State, TeamNFT {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let admin = account::create_account_for_test(@overmind);
        init_module(&admin);

        let player_name_list = vector[
            b"Tony",
            b"Adam",
            b"Dan",
            b"TC",
            b"John",
            b"Rath",
        ];
        create_match_week(&admin, player_name_list);

        change_game_session(&admin, 0);

        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&aptos_framework);
        let resource_account_address = account::create_resource_address(&@overmind, b"sport fantasy");
        aptos_coin::mint(&aptos_framework, resource_account_address, 24 * 2000000);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let account = account::create_account_for_test(@0xCAFE);
        let player1_id = 0;
        let player2_id = 1;
        let player3_id = 2;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xDAD);
        let player1_id = 0;
        let player2_id = 2;
        let player3_id = 3;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xC0FFEE);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);

        let player_goals = vector[
            0,
            1,
            1,
            0,
            0,
            1,
        ];
        let player_assists = vector[
            1,
            1,
            0,
            0,
            1,
            1,
        ];
        announce_with_stats(&admin, player_goals, player_assists);

        let player_name_list = vector[
            b"John",
            b"Paul",
            b"George",
            b"Ringo",
            b"Beatles",
            b"Liverpool",
        ];
        create_match_week(&admin, player_name_list);

        change_game_session(&admin, 0);

        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xC0FFEED);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xC0FF);
        let player1_id = 3;
        let player2_id = 2;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 2;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 1;
        let player2_id = 2;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);

        let resource_account_address = account::create_resource_address(&@overmind, b"sport fantasy");

        let expected_token_address = token::create_token_address(
            &resource_account_address, 
            &string::utf8(b"TeamNFT Collection"),
            &string::utf8(b"TeamNFT:1/0")
        );
        assert!(
            object::is_object(expected_token_address) == true, 
            0
        );
        let team_token = object::address_to_object<TeamNFT>(expected_token_address);
        let description = string::utf8( b"Overmind Sport Fantasy TeamNFT");
        assert!(
            token::description<TeamNFT>(team_token) == description, 
            0
        );
        assert!(
            token::name<TeamNFT>(team_token) == string::utf8(b"TeamNFT:1/0"), 
            0
        );
        assert!(
            token::uri<TeamNFT>(team_token) == string::utf8(b"ovm.team"), 
            0
        );
        assert!(
            option::is_none(&token::royalty<TeamNFT>(team_token)) == true, 
            0
        );

        let expected_token_address = token::create_token_address(
            &resource_account_address, 
            &string::utf8(b"TeamNFT Collection"),
            &string::utf8(b"TeamNFT:1/1")
        );
        assert!(
            object::is_object(expected_token_address) == true, 
            0
        );
        let team_token = object::address_to_object<TeamNFT>(expected_token_address);
        let description = string::utf8( b"Overmind Sport Fantasy TeamNFT");
        assert!(
            token::description<TeamNFT>(team_token) == description, 
            0
        );
        assert!(
            token::name<TeamNFT>(team_token) == string::utf8(b"TeamNFT:1/1"), 
            0
        );
        assert!(
            token::uri<TeamNFT>(team_token) == string::utf8(b"ovm.team"), 
            0
        );
        assert!(
            option::is_none(&token::royalty<TeamNFT>(team_token)) == true, 
            0
        );


        let expected_token_address = token::create_token_address(
            &resource_account_address, 
            &string::utf8(b"TeamNFT Collection"),
            &string::utf8(b"TeamNFT:1/2")
        );
        assert!(
            object::is_object(expected_token_address) == true, 
            0
        );
        let team_token = object::address_to_object<TeamNFT>(expected_token_address);
        let description = string::utf8( b"Overmind Sport Fantasy TeamNFT");
        assert!(
            token::description<TeamNFT>(team_token) == description, 
            0
        );
        assert!(
            token::name<TeamNFT>(team_token) == string::utf8(b"TeamNFT:1/2"), 
            0
        );
        assert!(
            token::uri<TeamNFT>(team_token) == string::utf8(b"ovm.team"), 
            0
        );
        assert!(
            option::is_none(&token::royalty<TeamNFT>(team_token)) == true, 
            0
        );

        let player_goals = vector[
            0,
            1,
            1,
            0,
            0,
            1,
        ];
        let player_assists = vector[
            1,
            1,
            0,
            0,
            1,
            1,
        ];
        announce_with_stats(&admin, player_goals, player_assists);

        let player_name_list = vector[
            b"John",
            b"Paul",
            b"George",
            b"Ringo",
            b"Beatles",
            b"Liverpool",
        ];
        create_match_week(&admin, player_name_list);

        change_game_session(&admin, 0);

        let account = account::create_account_for_test(@0xC0F);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xC0FFEEEEE);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xC000FF);
        let player1_id = 3;
        let player2_id = 2;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 2;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 1;
        let player2_id = 2;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);

        let expected_token_address = token::create_token_address(
            &resource_account_address, 
            &string::utf8(b"TeamNFT Collection"),
            &string::utf8(b"TeamNFT:2/0")
        );
        assert!(
            object::is_object(expected_token_address) == true, 
            0
        );
        let team_token = object::address_to_object<TeamNFT>(expected_token_address);
        let description = string::utf8( b"Overmind Sport Fantasy TeamNFT");
        assert!(
            token::description<TeamNFT>(team_token) == description, 
            0
        );
        assert!(
            token::name<TeamNFT>(team_token) == string::utf8(b"TeamNFT:2/0"), 
            0
        );
        assert!(
            token::uri<TeamNFT>(team_token) == string::utf8(b"ovm.team"), 
            0
        );
        assert!(
            option::is_none(&token::royalty<TeamNFT>(team_token)) == true, 
            0
        );

        let expected_token_address = token::create_token_address(
            &resource_account_address, 
            &string::utf8(b"TeamNFT Collection"),
            &string::utf8(b"TeamNFT:2/1")
        );
        assert!(
            object::is_object(expected_token_address) == true, 
            0
        );
        let team_token = object::address_to_object<TeamNFT>(expected_token_address);
        let description = string::utf8( b"Overmind Sport Fantasy TeamNFT");
        assert!(
            token::description<TeamNFT>(team_token) == description, 
            0
        );
        assert!(
            token::name<TeamNFT>(team_token) == string::utf8(b"TeamNFT:2/1"), 
            0
        );
        assert!(
            token::uri<TeamNFT>(team_token) == string::utf8(b"ovm.team"), 
            0
        );
        assert!(
            option::is_none(&token::royalty<TeamNFT>(team_token)) == true, 
            0
        );

        

        let player_goals = vector[
            0,
            1,
            1,
            0,
            0,
            1,
        ];
        let player_assists = vector[
            1,
            1,
            0,
            0,
            1,
            1,
        ];
        announce_with_stats(&admin, player_goals, player_assists);

        let player_name_list = vector[
            b"John",
            b"Paul",
            b"George",
            b"Ringo",
            b"Beatles",
            b"Liverpool",
        ];
        create_match_week(&admin, player_name_list);

        change_game_session(&admin, 0);

        let resource_account = account::create_resource_address(&@overmind, b"sport fantasy");
        let state = borrow_global<State>(resource_account);
        assert!(event::counter<CreateTeamNFTEvent>(&state.event_handlers.create_team_events) == 24, 0);
        assert!(event::counter<AnnounceResultEvent>(&state.event_handlers.announce_result_events) == 3, 0);
        assert!(event::counter<ChangeGameSessionEvent>(&state.event_handlers.change_game_session_events) == 7, 0);
        assert!(event::counter(&state.event_handlers.claim_reward_events) == 0, 6);
    }

    #[test]
    fun test_create_team_and_announce_claim_three_matchweeks_success() acquires State, TeamNFT {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let admin = account::create_account_for_test(@overmind);
        init_module(&admin);

        let player_name_list = vector[
            b"Tony",
            b"Adam",
            b"Dan",
            b"TC",
            b"John",
            b"Rath",
        ];
        create_match_week(&admin, player_name_list);

        change_game_session(&admin, 0);

        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&aptos_framework);
        let resource_account_address = account::create_resource_address(&@overmind, b"sport fantasy");
        aptos_coin::mint(&aptos_framework, resource_account_address, 24 * 2000000);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let account = account::create_account_for_test(@0xCAFE);
        let player1_id = 0;
        let player2_id = 1;
        let player3_id = 2;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xDAD);
        let player1_id = 0;
        let player2_id = 2;
        let player3_id = 3;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xC0FFEE);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);

        let player_goals = vector[
            0,
            1,
            1,
            0,
            0,
            1,
        ];
        let player_assists = vector[
            1,
            1,
            0,
            0,
            1,
            1,
        ];
        announce_with_stats(&admin, player_goals, player_assists);

        let player_name_list = vector[
            b"John",
            b"Paul",
            b"George",
            b"Ringo",
            b"Beatles",
            b"Liverpool",
        ];
        create_match_week(&admin, player_name_list);

        change_game_session(&admin, 0);

        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xC0FFEED);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xC0FF);
        let player1_id = 3;
        let player2_id = 2;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 2;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 1;
        let player2_id = 2;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);

        let player_goals = vector[
            0,
            1,
            1,
            0,
            0,
            1,
        ];
        let player_assists = vector[
            1,
            1,
            0,
            0,
            1,
            1,
        ];
        announce_with_stats(&admin, player_goals, player_assists);

        let player_name_list = vector[
            b"John",
            b"Paul",
            b"George",
            b"Ringo",
            b"Beatles",
            b"Liverpool",
        ];
        create_match_week(&admin, player_name_list);

        change_game_session(&admin, 0);

        let account = account::create_account_for_test(@0xC0F);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xC0FFEEEEE);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xC000FF);
        let player1_id = 3;
        let player2_id = 2;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 2;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 1;
        let player2_id = 2;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);

        let player_goals = vector[
            0,
            1,
            1,
            0,
            0,
            1,
        ];
        let player_assists = vector[
            1,
            1,
            0,
            0,
            1,
            1,
        ];
        announce_with_stats(&admin, player_goals, player_assists);
        let resource_account_address = account::create_resource_address(&@overmind, b"sport fantasy");
        let state = borrow_global<State>(resource_account_address);
        assert!(event::counter<CreateTeamNFTEvent>(&state.event_handlers.create_team_events) == 24, 0);
        assert!(event::counter<AnnounceResultEvent>(&state.event_handlers.announce_result_events) == 3, 0);
        move state;

        let match_week = 0;
        while (match_week < 2) {
            let i = 0;
            while (true) {
                let resource_account_address = account::create_resource_address(&@overmind, b"sport fantasy");
        let state = borrow_global<State>(resource_account_address);
                let team_id_to_nft_address_list = state.team_id_to_nft_address_list;
                let team_id_to_nft_address = vector::borrow(&team_id_to_nft_address_list, match_week);
                let team_count = simple_map::length<u64,address>(team_id_to_nft_address);
                if (i >= team_count) {
                    break
                };
                let team_id = i;
                let team_nft_address = *simple_map::borrow<u64, address>(team_id_to_nft_address, &team_id);
                let team_obj = object::address_to_object<TeamNFT>(team_nft_address);
                let team_owner = object::owner(team_obj);
                let team = borrow_global<TeamNFT>(team_nft_address);
                let team_rank = team.rank;
                move state;
                move team;
                let owner_signer = account::create_signer_for_test(team_owner);

                let balance_before = 0;
                if (coin::is_account_registered<AptosCoin>(signer::address_of(&owner_signer))) {
                    balance_before = coin::balance<AptosCoin>(signer::address_of(&owner_signer));
                };
                claim_reward(&owner_signer, (match_week as u8), team_id);
                if (team_rank > 0 && team_rank <= 10) {
                    assert!(coin::balance<AptosCoin>(signer::address_of(&owner_signer)) - balance_before == 2000000, 0);
                };

                i = i + 1;
            };

            match_week = match_week + 1;
        };

        let resource_account = account::create_resource_address(&@overmind, b"sport fantasy");
        let state = borrow_global<State>(resource_account);
        assert!(event::counter(&state.event_handlers.create_team_events) == 24, 6);
        assert!(event::counter(&state.event_handlers.announce_result_events) == 3, 6);
        assert!(event::counter(&state.event_handlers.claim_reward_events) == 14, 6);
        assert!(event::counter(&state.event_handlers.change_game_session_events) == 6, 6);
    }

    #[test]
    #[expected_failure(abort_code = ECodeForAllErrors, location = Self)]
    fun test_claim_failure_matchweek_does_not_exist() acquires State, TeamNFT {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let admin = account::create_account_for_test(@overmind);
        init_module(&admin);

        let player_name_list = vector[
            b"Tony",
            b"Adam",
            b"Dan",
            b"TC",
            b"John",
            b"Rath",
        ];
        create_match_week(&admin, player_name_list);

        change_game_session(&admin, 0);

        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&aptos_framework);
        let resource_account_address = account::create_resource_address(&@overmind, b"sport fantasy");
        aptos_coin::mint(&aptos_framework, resource_account_address, 24 * 2000000);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let account = account::create_account_for_test(@0xCAFE);
        let player1_id = 0;
        let player2_id = 1;
        let player3_id = 2;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xDAD);
        let player1_id = 0;
        let player2_id = 2;
        let player3_id = 3;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xC0FFEE);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);

        let player_goals = vector[
            0,
            1,
            1,
            0,
            0,
            1,
        ];
        let player_assists = vector[
            1,
            1,
            0,
            0,
            1,
            1,
        ];
        announce_with_stats(&admin, player_goals, player_assists);

        let resource_account_address = account::create_resource_address(&@overmind, b"sport fantasy");
        let state = borrow_global<State>(resource_account_address);
        assert!(event::counter<CreateTeamNFTEvent>(&state.event_handlers.create_team_events) == 4, 0);
        assert!(event::counter<AnnounceResultEvent>(&state.event_handlers.announce_result_events) == 1, 0);
        move state;

        claim_reward(&account, 10, 0);
    }

    #[test]
    #[expected_failure(abort_code = ECodeForAllErrors, location = Self)]
    fun test_claim_failure_team_does_not_exist() acquires State, TeamNFT {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let admin = account::create_account_for_test(@overmind);
        init_module(&admin);

        let player_name_list = vector[
            b"Tony",
            b"Adam",
            b"Dan",
            b"TC",
            b"John",
            b"Rath",
        ];
        create_match_week(&admin, player_name_list);

        change_game_session(&admin, 0);

        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&aptos_framework);
        let resource_account_address = account::create_resource_address(&@overmind, b"sport fantasy");
        aptos_coin::mint(&aptos_framework, resource_account_address, 24 * 2000000);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let account = account::create_account_for_test(@0xCAFE);
        let player1_id = 0;
        let player2_id = 1;
        let player3_id = 2;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xDAD);
        let player1_id = 0;
        let player2_id = 2;
        let player3_id = 3;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xC0FFEE);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);

        let player_goals = vector[
            0,
            1,
            1,
            0,
            0,
            1,
        ];
        let player_assists = vector[
            1,
            1,
            0,
            0,
            1,
            1,
        ];
        announce_with_stats(&admin, player_goals, player_assists);

        let resource_account_address = account::create_resource_address(&@overmind, b"sport fantasy");
        let state = borrow_global<State>(resource_account_address);
        assert!(event::counter<CreateTeamNFTEvent>(&state.event_handlers.create_team_events) == 4, 0);
        assert!(event::counter<AnnounceResultEvent>(&state.event_handlers.announce_result_events) == 1, 0);
        move state;

        claim_reward(&account, 0, 10);
    }

    #[test]
    #[expected_failure(abort_code = ECodeForAllErrors, location = Self)]
    fun test_claim_failure_not_owned_team() acquires State, TeamNFT {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let admin = account::create_account_for_test(@overmind);
        init_module(&admin);

        let player_name_list = vector[
            b"Tony",
            b"Adam",
            b"Dan",
            b"TC",
            b"John",
            b"Rath",
        ];
        create_match_week(&admin, player_name_list);

        change_game_session(&admin, 0);

        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&aptos_framework);
        let resource_account_address = account::create_resource_address(&@overmind, b"sport fantasy");
        aptos_coin::mint(&aptos_framework, resource_account_address, 24 * 2000000);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        let account = account::create_account_for_test(@0xCAFE);
        let player1_id = 0;
        let player2_id = 1;
        let player3_id = 2;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xDAD);
        let player1_id = 0;
        let player2_id = 2;
        let player3_id = 3;
        create_team(&account, player1_id, player2_id, player3_id);
        let account = account::create_account_for_test(@0xC0FFEE);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);
        let player1_id = 3;
        let player2_id = 4;
        let player3_id = 5;
        create_team(&account, player1_id, player2_id, player3_id);

        let player_goals = vector[
            0,
            1,
            1,
            0,
            0,
            1,
        ];
        let player_assists = vector[
            1,
            1,
            0,
            0,
            1,
            1,
        ];
        announce_with_stats(&admin, player_goals, player_assists);

        let resource_account_address = account::create_resource_address(&@overmind, b"sport fantasy");
        let state = borrow_global<State>(resource_account_address);
        assert!(event::counter<CreateTeamNFTEvent>(&state.event_handlers.create_team_events) == 4, 0);
        assert!(event::counter<AnnounceResultEvent>(&state.event_handlers.announce_result_events) == 1, 0);
        move state;

        let account = account::create_account_for_test(@0x000);
        claim_reward(&account, 0, 0);
    }

    #[test]
    fun test_change_game_session_success() acquires State {

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let admin = account::create_account_for_test(@overmind);
        init_module(&admin);

        let player_name_list = vector[
            b"Tony",
            b"Adam",
            b"Dan",
            b"TC",
            b"John",
            b"Rath",
        ];
        create_match_week(&admin, player_name_list);

        let resource_account_address = account::create_resource_address(&@overmind, b"sport fantasy");
        let state = borrow_global<State>(resource_account_address);
        assert!(state.game_session == 1, 0);

        change_game_session(&admin, 0);
        let resource_account_address = account::create_resource_address(&@overmind, b"sport fantasy");
        let state = borrow_global<State>(resource_account_address);
        assert!(state.game_session == 0, 0);
        assert!(event::counter<ChangeGameSessionEvent>(&state.event_handlers.change_game_session_events) == 1, 0);

        change_game_session(&admin, 2);
        let resource_account = account::create_resource_address(&@overmind, b"sport fantasy");
        let state = borrow_global<State>(resource_account);
        assert!(state.game_session == 2, 0);
        assert!(event::counter(&state.event_handlers.create_team_events) == 0, 6);
        assert!(event::counter(&state.event_handlers.announce_result_events) == 0, 6);
        assert!(event::counter(&state.event_handlers.claim_reward_events) == 0, 6);
        assert!(event::counter(&state.event_handlers.change_game_session_events) == 2, 6);
    }

    #[test]
    #[expected_failure(abort_code = ECodeForAllErrors, location = Self)]
    fun test_change_game_session_failure_not_admin() acquires State {

        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let admin = account::create_account_for_test(@overmind);
        init_module(&admin);

        let player_name_list = vector[
            b"Tony",
            b"Adam",
            b"Dan",
            b"TC",
            b"John",
            b"Rath",
        ];
        create_match_week(&admin, player_name_list);

        let resource_account_address = account::create_resource_address(&@overmind, b"sport fantasy");
        let state = borrow_global<State>(resource_account_address);
        assert!(state.game_session == 1, 0);

        change_game_session(&aptos_framework, 0);
    }

    #[test]
    #[expected_failure(abort_code = ECodeForAllErrors, location = Self)]
    fun test_create_match_week_failure_to_less_players() acquires State {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let admin = account::create_account_for_test(@overmind);
        init_module(&admin);

        let player_name_list = vector[
            b"Tony",
            b"Adam",
            b"Dan",
            b"TC",
            b"John",
            b"Rath",
        ];
        create_match_week(&admin, player_name_list);

        change_game_session(&admin, 0);

        let player_name_list = vector[
            b"John",
            b"Paul",
        ];
        create_match_week(&admin, player_name_list);
    }

    #[test]
    fun test_create_match_week_success() acquires State {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let admin = account::create_account_for_test(@overmind);
        init_module(&admin);

        let player_name_list = vector[
            b"John",
            b"Paul",
            b"George",
            b"Ringo",
            b"Beatles",
            b"Liverpool",
            b"Hey Jude",
        ];
        create_match_week(&admin, player_name_list);

        let resource_account_address = account::create_resource_address(&@overmind, b"sport fantasy");
        let state = borrow_global<State>(resource_account_address);
        assert!(state.match_week == 0, 0);

        assert!(vector::length(&state.player_list) == 7, 2);
        assert!(vector::borrow(&state.player_list, 0).id == 0, 3);
        assert!(vector::borrow(&state.player_list, 0).name == b"John", 4);
        assert!(vector::borrow(&state.player_list, 1).id == 1, 5);
        assert!(vector::borrow(&state.player_list, 1).name == b"Paul", 6);
        assert!(vector::borrow(&state.player_list, 2).id == 2, 7);
        assert!(vector::borrow(&state.player_list, 2).name == b"George", 8);
        assert!(vector::borrow(&state.player_list, 3).id == 3, 9);
        assert!(vector::borrow(&state.player_list, 3).name == b"Ringo", 10);
        assert!(vector::borrow(&state.player_list, 4).id == 4, 11);
        assert!(vector::borrow(&state.player_list, 4).name == b"Beatles", 12);
        assert!(vector::borrow(&state.player_list, 5).id == 5, 13);
        assert!(vector::borrow(&state.player_list, 5).name == b"Liverpool", 14);
        assert!(vector::borrow(&state.player_list, 6).id == 6, 15);
        assert!(vector::borrow(&state.player_list, 6).name == b"Hey Jude", 16);
        

        assert!(event::counter(&state.event_handlers.create_team_events) == 0, 6);
        assert!(event::counter(&state.event_handlers.announce_result_events) == 0, 6);
        assert!(event::counter(&state.event_handlers.claim_reward_events) == 0, 6);
        assert!(event::counter(&state.event_handlers.change_game_session_events) == 0, 6);
    }

    #[test]
    #[expected_failure(abort_code = ECodeForAllErrors, location = Self)]
    fun test_create_match_week_failure_not_admin() acquires State {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let admin = account::create_account_for_test(@overmind);
        init_module(&admin);

        let player_name_list = vector[
            b"John",
            b"Paul",
            b"George",
            b"Ringo",
            b"Beatles",
            b"Liverpool",
            b"Hey Jude",
        ];
        create_match_week(&aptos_framework, player_name_list);
    }
}